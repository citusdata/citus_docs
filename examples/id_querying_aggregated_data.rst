.. _id_querying_aggregated_data:

Querying Aggregated Data
#########################

As discussed in the pervious section, users may want to aggregate their distributed tables in order to receive fast query responses. To do that with hash distributed tables, you can follow the steps below.

**1. Create Hash Partitioned Aggregate table and worker shards**
  
::

    /opt/citusdb/4.0/bin/psql -h localhost -d postgres
    CREATE TABLE github_events_hourly
    (
        event_type text,
        repo_id bigint,
        created_hour timestamp,
        event_count bigint,
        statistics jsonb
    );

    SELECT master_create_distributed_table('github_events_hourly', 'repo_id');
    SELECT master_create_worker_shards('github_events_hourly', 16, 2);

There are few points to note here. Firstly, we use the same aggregate table schema as we used in the previous example.

Secondly, we distribute the aggregate table by the same column as the raw data tables and create the same number of worker shards i.e. 16 for both the tables. This ensures that shards for both the tables are colocated. Hence, all the shards having the same hash ranges will reside on the same node. This will allow us to run the aggregation queries in a distributed way on the worker nodes without moving any data across the nodes.

**2. Use a custom UDF to aggregate data from the github_events table into the github_events_hourly table**

To make the process of aggregating distributed tables in parallel easier, CitusDB’s next release will come with a user defined function master_aggregate_table_shards(). The signature of the function is as defined below.

::

    master_aggregate_table_shards(source table, destination table, aggregation_query);

Since, we created two tables with the same number of shards, there is a 1:1 mapping between shards of the raw data table and the aggregate table. This function will take the aggregation query passed as an argument and run it on each shard of the source table. The results of this query will then be stored into the corresponding destination table shard.

This UDF is under development and will be a part of CitusDB’s next release. If you want to use this functionality or learn more about the UDF and its implementation, please get in touch with us at engage@citusdata.com.

**3. Query the aggregated table**

Once the data is stored into the aggregate table, users can run their queries on them.

::

    SELECT
        event_type, date_part('hour', created_hour), to_char(created_hour,'day'), sum(event_count)
    FROM
        github_events_hourly
    WHERE
        repo_id = '724712'
    GROUP BY
        event_type, date_part('hour', created_hour), to_char(created_hour,'day')
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

With this we end our discussion about how users can use CitusDB to address different type of real-time dashboard use cases. We will soon be adding another example, which explains how users can run session analytics on their data using CitusDB. You can also visit the :ref:`user_guide_index` section of our documentation to learn about CitusDB commands in detail.
