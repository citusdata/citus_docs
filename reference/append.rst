.. _append_distribution:

Append Distribution
###################

.. note::

  Append distribution is a specialized technique which requires
  care to use efficiently. Hash distribution is a better choice
  for most situations.

While Citus' most common use cases involve hash data distribution,
it can also distribute timeseries data across a variable number of
shards by their order in time. This section provides a short reference
to loading, deleting, and maninpulating timeseries data.

As the name suggests, append based distribution is more suited to
append-only use cases. This typically includes event based data
which arrives in a time-ordered series. You can then distribute
your largest tables by time, and batch load your events into Citus
in intervals of N minutes. This data model can be generalized to a
number of time series use cases; for example, each line in a website's
log file, machine activity logs or aggregated website events. Append
based distribution supports more efficient range queries. This is
because given a range query on the distribution key, the Citus query
planner can easily determine which shards overlap that range and
send the query to only to relevant shards.

Hash based distribution is more suited to cases where you want to
do real-time inserts along with analytics on your data or want to
distribute by a non-ordered column (eg. user id). This data model
is relevant for real-time analytics use cases; for example, actions
in a mobile application, user website events, or social media
analytics. In this case, Citus will maintain minimum and maximum
hash ranges for all the created shards. Whenever a row is inserted,
updated or deleted, Citus will redirect the query to the correct
shard and issue it locally. This data model is more suited for doing
co-located joins and for queries involving equality based filters
on the distribution column.

Citus uses slightly different syntaxes for creation and manipulation
of append and hash distributed tables. Also, the operations supported
on the tables differ based on the distribution method chosen. In the
sections that follow, we describe the syntax for creating append
distributed tables, and also describe the operations which can be
done on them.

Creating and Distributing Tables
---------------------------------

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:

    ::

        export PATH=/usr/lib/postgresql/9.6/:$PATH


We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

To create an append distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/current/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

::

    psql -h localhost -d postgres
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

Next, you can use the create_distributed_table() function to mark the table as an append distributed table and specify its distribution column.

::

    SELECT create_distributed_table('github_events', 'created_at', 'append');

This function informs Citus that the github_events table should be distributed by append on the created_at column. Note that this method doesn't enforce a particular distribution; it merely tells the database to keep minimum and maximum values for the created_at column in each shard which are later used by the database for optimizing queries.

Expiring Data
---------------

In append distribution, users typically want to track data only for the last few months / years. In such cases, the shards that are no longer needed still occupy disk space. To address this, Citus provides a user defined function master_apply_delete_command() to delete old shards. The function takes a `DELETE <http://www.postgresql.org/docs/current/static/sql-delete.html>`_ command as input and deletes all the shards that match the delete criteria with their metadata.

The function uses shard metadata to decide whether or not a shard needs to be deleted, so it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards are selected for deletion. The UDF then connects to the worker nodes and issues DROP commands for all the shards which need to be deleted. If a drop query for a particular shard replica fails, then that replica is marked as TO DELETE. The shard replicas which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

The example below deletes those shards from the github_events table which have all rows with created_at >= '2015-01-01 00:00:00'. Note that the table is distributed on the created_at column.

::

    SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE created_at >= ''2015-01-01 00:00:00''');
     master_apply_delete_command
    -----------------------------
                               3
    (1 row)

To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.  Please note that this function only deletes complete shards and not individual rows from shards. If your use case requires deletion of individual rows in real-time, see the section below about deleting data.

Deleting Data
---------------

The most flexible way to modify or delete rows throughout a Citus cluster with regular SQL statements:

::

  DELETE FROM github_events
  WHERE created_at >= '2015-01-01 00:03:00';

Unlike master_apply_delete_command, standard SQL works at the row- rather than shard-level to modify or delete all rows that match the condition in the where clause. It deletes rows regardless of whether they comprise an entire shard.

Dropping Tables
---------------

You can use the standard PostgreSQL `DROP TABLE <http://www.postgresql.org/docs/current/static/sql-droptable.html>`_
command to remove your append distributed tables. As with regular tables, DROP TABLE removes any
indexes, rules, triggers, and constraints that exist for the target table. In addition, it also
drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;

Data Loading
------------

Citus supports two methods to load data into your append distributed tables. The first one is suitable for bulk loads from files and involves using the \\copy command. For use cases requiring smaller, incremental data loads, Citus provides two user defined functions. We describe each of the methods and their usage below.

Bulk load using \\copy
$$$$$$$$$$$$$$$$$$$$$$$

The `\\copy <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_
command is used to copy data from a file to a distributed table while handling
replication and failures automatically. You can also use the server side `COPY command <http://www.postgresql.org/docs/current/static/sql-copy.html>`_. 
In the examples, we use the \\copy command from psql, which sends a COPY .. FROM STDIN to the server and reads files on the client side, whereas COPY from a file would read the file on the server.

You can use \\copy both on the coordinator and from any of the workers. When using it from the worker, you need to add the master_host option. Behind the scenes, \\copy first opens a connection to the coordinator using the provided master_host option and uses master_create_empty_shard to create a new shard. Then, the command connects to the workers and copies data into the replicas until the size reaches shard_max_size, at which point another new shard is created. Finally, the command fetches statistics for the shards and updates the metadata.

::

    SET citus.shard_max_size TO '64MB';
    \copy github_events from 'github_events-2015-01-01-0.csv' WITH (format CSV, master_host 'coordinator-host')

Citus assigns a unique shard id to each new shard and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. One can connect to the worker postgres instances to view or run commands on individual shards.

By default, the \\copy command depends on two configuration parameters for its behavior. These are called citus.shard_max_size and citus.shard_replication_factor.

(1) **citus.shard_max_size :-** This parameter determines the maximum size of a shard created using \\copy, and defaults to 1 GB. If the file is larger than this parameter, \\copy will break it up into multiple shards.
(2) **citus.shard_replication_factor :-** This parameter determines the number of nodes each shard gets replicated to, and defaults to one. Set it to two if you want Citus to replicate data automatically and provide fault tolerance. You may want to increase the factor even higher if you run large clusters and observe node failures on a more frequent basis.

.. note::
    The configuration setting citus.shard_replication_factor can only be set on the coordinator node.

Please note that you can load several files in parallel through separate database connections or from different nodes. It is also worth noting that \\copy always creates at least one shard and does not append to existing shards. You can use the method described below to append to previously created shards.

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Incremental loads by appending to existing shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The \\copy command always creates a new shard when it is used and is best suited for bulk loading of data. Using \\copy to load smaller data increments will result in many small shards which might not be ideal. In order to allow smaller, incremental loads into append distributed tables, Citus provides 2 user defined functions. They are master_create_empty_shard() and master_append_table_to_shard().

master_create_empty_shard() can be used to create new empty shards for a table. This function also replicates the empty shard to citus.shard_replication_factor number of nodes like the \\copy command.

master_append_table_to_shard() can be used to append the contents of a PostgreSQL table to an existing shard. This allows the user to control the shard to which the rows will be appended. It also returns the shard fill ratio which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created.

To use the above functionality, you can first insert incoming data into a regular PostgreSQL table. You can then create an empty shard using master_create_empty_shard(). Then, using master_append_table_to_shard(), you can append the contents of the staging table to the specified shard, and then subsequently delete the data from the staging table. Once the shard fill ratio returned by the append function becomes close to 1, you can create a new shard and start appending to the new one.

::

    SELECT * from master_create_empty_shard('github_events');
    master_create_empty_shard
    ---------------------------
                    102089
    (1 row)

    SELECT * from master_append_table_to_shard(102089, 'github_events_temp', 'master-101', 5432);
    master_append_table_to_shard 
    ------------------------------
            0.100548
    (1 row)

To learn more about the two UDFs, their arguments and usage, please visit the :ref:`user_defined_functions` section of the documentation.

Increasing data loading performance
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The methods described above enable you to achieve high bulk load rates which are sufficient for most use cases. If you require even higher data load rates, you can use the functions described above in several ways and write scripts to better control sharding and data loading. The next section explains how to go even faster.

Scaling Data Ingestion
----------------------

If your use-case does not require real-time ingests, then using append distributed tables will give you the highest ingest rates. This approach is more suitable for use-cases which use time-series data and where the database can be a few minutes or more behind.

Coordinator Node Bulk Ingestion (100k/s-200k/s)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

To ingest data into an append distributed table, you can use the `COPY <http://www.postgresql.org/docs/current/static/sql-copy.html>`_ command, which will create a new shard out of the data you ingest. COPY can break up files larger than the configured citus.shard_max_size into multiple shards. COPY for append distributed tables only opens connections for the new shards, which means it behaves a bit differently than COPY for hash distributed tables, which may open connections for all shards. A COPY for append distributed tables command does not ingest rows in parallel over many connections, but it is safe to run many commands in parallel.

::

    -- Set up the events table
    CREATE TABLE events (time timestamp, data jsonb);
    SELECT create_distributed_table('events', 'time', 'append');

    -- Add data into a new staging table
    \COPY events FROM 'path-to-csv-file' WITH CSV

COPY creates new shards every time it is used, which allows many files to be ingested simultaneously, but may cause issues if queries end up involving thousands of shards. An alternative way to ingest data is to append it to existing shards using the master_append_table_to_shard function. To use master_append_table_to_shard, the data needs to be loaded into a staging table and some custom logic to select an appropriate shard is required.

::

    -- Prepare a staging table
    CREATE TABLE stage_1 (LIKE events);
    \COPY stage_1 FROM 'path-to-csv-file WITH CSV

    -- In a separate transaction, append the staging table
    SELECT master_append_table_to_shard(select_events_shard(), 'stage_1', 'coordinator-host', 5432);

An example of a shard selection function is given below. It appends to a shard until its size is greater than 1GB and then creates a new one, which has the drawback of only allowing one append at a time, but the advantage of bounding shard sizes.

::

    CREATE OR REPLACE FUNCTION select_events_shard() RETURNS bigint AS $$
    DECLARE
      shard_id bigint;
    BEGIN
      SELECT shardid INTO shard_id
      FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
      WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024;

      IF shard_id IS NULL THEN
        /* no shard smaller than 1GB, create a new one */
        SELECT master_create_empty_shard('events') INTO shard_id;
      END IF;

      RETURN shard_id;
    END;
    $$ LANGUAGE plpgsql;

It may also be useful to create a sequence to generate a unique name for the staging table. This way each ingestion can be handled independently.

::

    -- Create stage table name sequence
    CREATE SEQUENCE stage_id_sequence;

    -- Generate a stage table name
    SELECT 'stage_'||nextval('stage_id_sequence');

To learn more about the master_append_table_to_shard and master_create_empty_shard UDFs, please visit the :ref:`user_defined_functions` section of the documentation.

Worker Node Bulk Ingestion (100k/s-1M/s)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

For very high data ingestion rates, data can be staged via the workers. This method scales out horizontally and provides the highest ingestion rates, but can be more complex to use. Hence, we recommend trying this method only if your data ingestion rates cannot be addressed by the previously described methods.

Append distributed tables support COPY via the worker, by specifying the address of the coordinator in a master_host option, and optionally a master_port option (defaults to 5432). COPY via the workers has the same general properties as COPY via the coordinator, except the initial parsing is not bottlenecked on the coordinator.

::

    psql -h worker-host-n -c "\COPY events FROM 'data.csv' WITH (FORMAT CSV, MASTER_HOST 'coordinator-host')"


An alternative to using COPY is to create a staging table and use standard SQL clients to append it to the distributed table, which is similar to staging data via the coordinator. An example of staging a file via a worker using psql is as follows:

::

    stage_table=$(psql -tA -h worker-host-n -c "SELECT 'stage_'||nextval('stage_id_sequence')")
    psql -h worker-host-n -c "CREATE TABLE $stage_table (time timestamp, data jsonb)"
    psql -h worker-host-n -c "\COPY $stage_table FROM 'data.csv' WITH CSV"
    psql -h coordinator-host -c "SELECT master_append_table_to_shard(choose_underutilized_shard(), '$stage_table', 'worker-host-n', 5432)"
    psql -h worker-host-n -c "DROP TABLE $stage_table"

The example above uses a choose_underutilized_shard function to select the shard to which to append. To ensure parallel data ingestion, this function should balance across many different shards.

An example choose_underutilized_shard function belows randomly picks one of the 20 smallest shards or creates a new one if there are less than 20 under 1GB. This allows 20 concurrent appends, which allows data ingestion of up to 1 million rows/s (depending on indexes, size, capacity).

::

    /* Choose a shard to which to append */
    CREATE OR REPLACE FUNCTION choose_underutilized_shard()
    RETURNS bigint LANGUAGE plpgsql
    AS $function$
    DECLARE
      shard_id bigint;
      num_small_shards int;
    BEGIN
      SELECT shardid, count(*) OVER () INTO shard_id, num_small_shards
      FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
      WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024
      GROUP BY shardid ORDER BY RANDOM() ASC;

      IF num_small_shards IS NULL OR num_small_shards < 20 THEN
        SELECT master_create_empty_shard('events') INTO shard_id;
      END IF;

      RETURN shard_id;
    END;
    $function$;
    
A drawback of ingesting into many shards concurrently is that shards may span longer time ranges, which means that queries for a specific time period may involve shards that contain a lot of data outside of that period.

In addition to copying into temporary staging tables, it is also possible to set up tables on the workers which can continuously take INSERTs. In that case, the data has to be periodically moved into a staging table and then appended, but this requires more advanced scripting.

Pre-processing Data in Citus
$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The format in which raw data is delivered often differs from the schema used in the database. For example, the raw data may be in the form of log files in which every line is a JSON object, while in the database table it is more efficient to store common values in separate columns. Moreover, a distributed table should always have a distribution column. Fortunately, PostgreSQL is a very powerful data processing tool. You can apply arbitrary pre-processing using SQL before putting the results into a staging table.

For example, assume we have the following table schema and want to load the compressed JSON logs from `githubarchive.org <http://www.githubarchive.org>`_:

::

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
    SELECT create_distributed_table('github_events', 'created_at', 'append');


To load the data, we can download the data, decompress it, filter out unsupported rows, and extract the fields in which we are interested into a staging table using 3 commands:

::

    CREATE TEMPORARY TABLE prepare_1 (data jsonb);

    -- Load a file directly from Github archive and filter out rows with unescaped 0-bytes
    COPY prepare_1 FROM PROGRAM
    'curl -s http://data.githubarchive.org/2016-01-01-15.json.gz | zcat | grep -v "\\u0000"'
    CSV QUOTE e'\x01' DELIMITER e'\x02';

    -- Prepare a staging table
    CREATE TABLE stage_1 AS
    SELECT (data->>'id')::bigint event_id,
           (data->>'type') event_type,
           (data->>'public')::boolean event_public,
           (data->'repo'->>'id')::bigint repo_id,
           (data->'payload') payload,
           (data->'actor') actor,
           (data->'org') org,
           (data->>'created_at')::timestamp created_at FROM prepare_1;

You can then use the master_append_table_to_shard function to append this staging table to the distributed table.

This approach works especially well when staging data via the workers, since the pre-processing itself can be scaled out by running it on many workers in parallel for different chunks of input data.

For a more complete example, see `Interactive Analytics on GitHub Data using PostgreSQL with Citus <https://www.citusdata.com/blog/14-marco/402-interactive-analytics-github-data-using-postgresql-citus>`_.
