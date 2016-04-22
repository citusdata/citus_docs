.. time_querying_aggregated_data:

Querying Aggregated Data
#########################

This type of data model is more applicable to users who want to load data into
their database at minutely, hourly or daily intervals. Users can aggregate their
data on the time interval using one of the approaches below, and store the
aggregated data in CitusDB. They can then serve real-time graphs grouped at the
desired time intervals by running queries on the aggregated data.

To aggregate the raw data into hourly / daily digests, users can choose one of
the following approaches:

* **Use an external system:** One option is to use an external system to capture the raw events data and aggregate it. Then, the aggregated data can be loaded into CitusDB. There are several tools which can be used for this step. You can see an `example setup <https://blog.cloudflare.com/scaling-out-postgresql-for-cloudflare-analytics-using-citusdb/>`_ for this approach where Cloudflare uses Kafka queues and Go aggregators to consume their log data and insert aggregated data with 1-minute granularity into their CitusDB cluster.

* **Use PostgreSQL to aggregate the data:** Another common approach is to append your raw events data into a PostgreSQL table and then run an aggregation query on top of the raw data. Then, you can load the aggregated data into a distributed table.

Below, we give an example of how you can use PostgreSQL to aggregate the Github
data and then run queries on it.

**1. Create local aggregation tables**

We first create a regular PostgreSQL table to store the incoming raw data. This
has the same schema as the table discussed in the previous section.

::

   /opt/citusdb/4.0/bin/psql -h localhost -d postgres
   CREATE TABLE github_events_local
    (
        event_id bigint,
        event_type text,
        event_public boolean,
        repo_id bigint,
        payload jsonb,
        repo jsonb,
        actor jsonb,
        org jsonb,
        created_at timestamp
    );

Next, we create the aggregation table. The schema for the aggregate table depends on the type of queries and intervals of aggregations. We will generate reports / graphs similar to github i.e. statistics (per-repo and global) for different types of events over different time filters. Hence, we aggregate the data on the repo_id and event_type columns on an hourly basis.

::

    CREATE TABLE github_events_hourly_local
    (
        event_type text,
        repo_id bigint,
        created_hour timestamp,
        event_count bigint,
        statistics jsonb
    );

Please note that this table is also created as a regular PostgreSQL table (i.e. without the distribute by append clause). We will append the aggregated data into a distributed table in subsequent steps.

One interesting field in this table schema is the statistics column. In the raw data schema, there is a payload column which stores event specific data. The statistics column can be used to store statistics about keys in that payload column for the set of events which have been aggregated into that row.

For example, the github events data has a event_type named IssuesEvent which is triggered when an issue’s status changes eg. opened, closed, or reopened. The statistics field in the rows corresponding to IssuesEvent will have a jsonb object having information about how many of those events were opened, how many were closed and how many were reopened ({"closed": "1", "opened": "3"}).

Such a schema allows you to store any kinds of statistics by just changing the aggregation query. You can choose to store total number of lines changed, name of the branch on which the event occurred, or any other information you would like.


**2. Create distributed aggregate table**

Next, we create the distributed aggregate table with the same schema as the PostgreSQL aggregate table but with the DISTRIBUTE BY APPEND clause.

::

    CREATE TABLE github_events_hourly
    (
        event_type text,
        repo_id bigint,
        created_hour timestamp,
        event_count bigint,
        statistics jsonb
    ) DISTRIBUTE BY APPEND (created_hour);

**3. Load raw data into the PostgreSQL table**

The users can then insert their incoming raw events data into the github_events table using the regular PostgreSQL INSERT commands. For the example however, we use the \copy command to copy one hour of data into the table.

::

    \copy github_events_local from 'github_events-2015-01-01-0.csv' WITH CSV

**4. Aggregation on a hourly basis**

Once the github_events table has an hour of data, users can run an aggregation query on that table and store the aggregated results into the github_events_hourly table.

To do this aggregation step, we first create a user defined function which takes in a array of strings and returns a json object with each object and its count in that array. This function will be used later to generate the statistics column in the aggregated table.

::

    CREATE FUNCTION count_elements(text[]) RETURNS json AS
    $BODY$
    select ('{' || a || '}')::json
        from
        (
        select string_agg('"' || i || '":"' || c || '"', ',') a
            FROM
            (
                SELECT i, count(*) c
                FROM
                (SELECT unnest($1::text[]) i) i GROUP BY i ORDER BY c DESC
            ) foo
        ) bar;
    $BODY$    
    LANGUAGE SQL;
 
In the next step, we run a SQL query which aggregates the raw events data on the basis of event_type, repo_id and the hour, and then stores the relevant statistics about those events in the statistics column of the github_events_hourly_local table. Please note that you can store more information from the events’ payload column by modifying the aggregation query.

::

    INSERT INTO github_events_hourly_local (
    select
        event_type, repo_id, date_trunc('hour', created_at) as created_hour, count(*), 
        (CASE
            when
                event_type = 'IssuesEvent'
            then count_elements(array_agg(payload->>'action'))::jsonb
            when event_type = 'GollumEvent'
            then count_elements(array_agg(payload->'pages'->0->>'action'))::jsonb
            when event_type = 'PushEvent'
            then count_elements(array_agg(payload->>'ref'))::jsonb
            when event_type = 'ReleaseEvent'
            then count_elements(array_agg(payload->'release'->>'tag_name'))::jsonb
            when event_type = 'CreateEvent'
            then count_elements(array_agg(payload->>'ref_type'))::jsonb
            when event_type = 'DeleteEvent'
            then count_elements(array_agg(payload->>'ref_type'))::jsonb
            when event_type = 'PullRequestEvent'
            then count_elements(array_agg(payload->>'action'))::jsonb
            else null
        end)
    from
        github_events_local
    where
        date_trunc('hour',created_at) = '2015-01-01 00:00:00'
    group by  
        event_type, repo_id, date_trunc('hour',created_at));
 
This way users can convert the raw data into aggregated tables on a hourly basis simply by changing the time filter in the above query.

Once you have the aggregate table, you can \stage or append the raw data into another distributed table. This way, if you have queries on a dimension other than the aggregated dimension, you can always lookup those results in the raw data. Once that is done, you can truncate the local table or delete those rows from it which have already been aggregated.

::

    TRUNCATE github_events_local ;

**5. Create an empty shard for the distributed table**

We then create a new shard for the distributed table by using the master_create_empty_shard UDF.

::

    select * from master_create_empty_shard('github_events_hourly');
     master_create_empty_shard
    ---------------------------
                      102014
    (1 row)

This function creates a new shard on the worker nodes which has the same schema as the master node table. Then, it replicates the empty shard to shard_replication_factor nodes. Finally, the function returns the shard id of the newly created shard.

**6. Append the aggregated table into a distributed table**

Then, we append the local aggregate table to the newly created shard using the master_append_table_to_shard UDF.

::


    select * from master_append_table_to_shard(102014, 'github_events_hourly_local', 'source-node-name', 5432);
     master_append_table_to_shard 
    ------------------------------
                      0.000473022
    (1 row)

master_append_table_to_shard() appends the contents of a PostgreSQL table to a shard of a distributed table. In this example, the function fetches the github_events_hourly_local table from the database server running on node 'source-node-name' with port number 5432 and appends it to the shard 102014. This source node name can be set to the hostname of the node which has the github_events_hourly_local table.

The function then returns the shard fill ratio which which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created. The maximum desired shard size can be configured using the shard_max_size parameter.

Once this data is appended to the distributed table, we can truncate the local table.

::

    TRUNCATE github_events_hourly_local;

**7. Download pre-aggregated data**

In the above steps, we have demonstrated how users can aggregate data within PostgreSQL for one hour of data. You can aggregate the data for all the six hours using the process described in step 4.

For ease of use, we download the already aggregated data and use it to describe the next steps.

::

    wget http://examples.citusdata.com/github_archive/github_events_aggregated-2015-01-01-{1..5}.csv.gz 
    gzip -d github_events_aggregated-2015-01-01-*.gz

**8. Load pre-aggregated data into distributed table**

If you are doing aggregation similar to the process described above, then your aggregated data will be in the github_events_hourly_local table. If you are using some other external tool for aggregation or downloading the pre-aggregated files, then you can load the data into that table before appending it to a distributed table.

::

    \copy github_events_hourly_local from 'github_events_aggregated-2015-01-01-1.csv' WITH CSV;

Please note that we store this data into a local table using \copy instead of using the \stage command. This is because the \stage command always creates a new shard when invoked. In this case, creating new shards for every hour of data will lead to a very high number of small shards in the system which might not be desirable. So, we load the data into PostgreSQL tables and then append them to a shard until we reach the desired size.

We then append this data into the previously created shard of the distributed table and then empty the local table.

::

    SELECT * from master_append_table_to_shard(102014, 'github_events_hourly_local', 'source-node-name', 5432);

    TRUNCATE github_events_hourly_local;

Similarly, you can repeat the above steps for the next four hours of data. Please note that you can run the master_create_empty_shard() to create new shards when the shard fill ratio returned by the UDF is close to one and the shard size is close to the shard_max_size. Then, you can begin appending to that shard by using the new shard id in the master_append_table_to_shard() UDF.

**9. Run queries on the distributed aggregate table**

After the above steps, you can run queries on your aggregated data. To generate the same reports as you did on the raw data, you can use the following queries on the aggregated table.

::

    SELECT
        event_type, date_part('hour', created_hour), to_char(created_hour,'day'), sum(event_count)
    FROM
        github_events_hourly
    WHERE
        repo_id = '724712'
    GROUP BY
        event_type, date_part('hour', created_hour), to_char(created_hour, 'day')
    ORDER BY
        event_type, date_part('hour', created_hour), to_char(created_hour, 'day');

    SELECT
        sum((statistics->>'opened')::int) as opened_issue_count,
        sum((statistics->>'closed')::int) as closed_issue_count,
        sum((statistics->>'reopened')::int) as reopened_issue_count
    FROM
        github_events_hourly
    WHERE
        event_type = 'IssuesEvent' AND
        created_hour >= '2015-01-01 00:00:00' AND
        created_hour <= '2015-01-01 02:00:00';

With this, we conclude our discussion about distributing data on the time dimension and running analytics queries for generating hourly / daily reports. In the next example, we discuss how we can partition the data on an identifier to do real time inserts into distributed tables.
