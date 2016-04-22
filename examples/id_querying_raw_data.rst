.. _id_querying_raw_data:

Querying Raw Data
##################

In this section, we discuss how users can setup hash partitioned tables on the repo_id column with the same github events data.

**1. Create hash partitioned raw data tables**

We define a hash partitioned table using the CREATE TABLE statement in the same way as you would do with a regular postgresql table. Please note that we use the same table schema as we used in the previous example.

::

    /opt/citusdb/4.0/bin/psql -h localhost -d postgres
    CREATE TABLE github_events
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

Next, we need to specify the distribution column for the table. This can be done by using the master_create_distributed_table() UDF.

::

    SELECT master_create_distributed_table('github_events', 'repo_id');

This UDF informs the database that the github_events table should be distributed by hash on the repo_id column.

**2. Create worker shards for the distributed table**

::
    
    SELECT master_create_worker_shards('github_events', 16, 2);

This UDF takes two arguments in addition to the table name; shard count and the replication factor. This example would create a total of 16 shards where each shard owns a portion of a hash token space and gets replicated on 2 worker nodes.

**3. Download sample data**

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

**4. Insert raw events data into github_events table**

Users can then use the standard PostgreSQL insert command to insert data into the github_events table. For now, we will use the copy_to_distributed_table script to populate the github_events table.

Before invoking the script, we set the PATH environment variable to include the CitusDB bin directory.

::
    
    export PATH=/opt/citusdb/4.0/bin/:$PATH

Next, you should set the environment variables which will be used as connection parameters while connecting to your postgres server. For example, to set the default database to postgres, you can run the command shown below.

::

    export PGDATABASE=postgres

After setting these environment variables, we load the 6 hours of data into the github_events table by invoking the copy_to_distributed_table script.

::

    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-0.csv github_events &
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-1.csv github_events &
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-2.csv github_events &
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-3.csv github_events &
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-4.csv github_events &
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01-5.csv github_events &

Please note that we run all the commands in background for them to execute in parallel. Also, it is worth noting here that hash partitioned tables are more suited for single row inserts as compared to bulk loads. However, we use the copy script here for simplicity reasons.

**5. Run queries on raw data**

We are now ready to run queries on the events data.

::

    -- Find the number of each event type on a per day and per hour graph for a particular repository. 
    SELECT
        event_type, date_part('hour', created_at) as hour, to_char(created_at, 'day'), count(*)
    FROM
        github_events
    WHERE
        repo_id = '724712'
    GROUP BY
        event_type, date_part('hour', created_at), to_char(created_at, 'day')
    ORDER BY
        event_type, date_part('hour', created_at), to_char(created_at, 'day');

::

    -- Find total count of issues opened, closed, and reopened in the first 3 hours.
    SELECT
        payload->'action', count(*)
    FROM
        github_events
    WHERE
        event_type = 'IssuesEvent' AND
        created_at >= '2015-01-01 00:00:00' AND
        created_at <= '2015-01-01 02:00:00'
    GROUP BY
        payload->'action';

As discussed in the previous sections, the hardware requirements of a cluster to get real-time query responses might not be cost effective. Therefore, users can create tables to aggregate their data on the time dimension and query the aggregated data to get fast query responses. In the next section, we discuss an approach to do this for hash partitioned tables partitioned on the repo_id column.
