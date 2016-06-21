.. _scaling_data_ingestion:

Scaling Out Data Ingestion
##########################

Citus lets you scale out data ingestion to very high rates, but there are several trade-offs to consider in terms of the throughput, durability, consistency and latency. In this section, we discuss several approaches to data ingestion and give examples of how to use them.

The best method to distribute tables and ingest your data depends on your use case requirements. Citus supports two distribution methods: append and hash; and the data ingestion methods differ between them. You can visit the :ref:`working_with_distributed_tables` section to learn about the tradeoffs associated with each distribution method.

Hash Distributed Tables
$$$$$$$$$$$$$$$$$$$$$$$

Hash distributed tables support ingestion using standard single row INSERT and UPDATE commands, as well as bulk ingestion through COPY.

Real-time Inserts (0-50k/s)
---------------------------

On the Citus master, you can perform INSERT commands directly on hash distributed tables. The advantage of using INSERT is that the new data is immediately visible to SELECT queries, and durably stored on multiple replicas.

When processing an INSERT, Citus first finds the right shard placements based on the value in the distribution column, then it connects to the workers storing the shard placements, and finally performs an INSERT on each of them. From the perspective of the user, the INSERT takes several milliseconds to process because of the round-trips to the workers, but the master can process other INSERTs in other sessions while waiting for a response. The master also keeps connections to the workers open within the same session, which means subsequent queries will see lower response times.

::

    -- Set up a distributed table containing counters
    CREATE TABLE counters (c_key text, c_date date, c_value int, primary key (c_key, c_date));
    SELECT master_create_distributed_table('counters', 'c_key', 'hash');
    SELECT master_create_worker_shards('counters', 128, 2);

    -- Enable timing to see reponse times
    \timing on

    -- First INSERT requires connection set-up, second will be faster
    INSERT INTO counters VALUES ('num_purchases', '2016-03-04', 12); -- Time: 10.314 ms
    INSERT INTO counters VALUES ('num_purchases', '2016-03-05', 5); -- Time: 3.132 ms

To reach high throughput rates, applications should send INSERTs over a many separate connections and keep connections open to avoid the initial overhead of connection set-up.

Real-time Updates (0-50k/s)
---------------------------

On the Citus master, you can also perform UPDATE, DELETE, and INSERT ... ON CONFLICT (UPSERT) commands on distributed tables. By default, these queries take an exclusive lock on the shard, which prevents concurrent modifications to guarantee that the commands are applied in the same order on all shard placements.

Given that every command requires several round-trips to the workers, and no two commands can run on the same shard at the same time, update throughput is very low by default. However, if you know that the order of the queries doesn't matter (they are commutative), then you can turn on citus.all_modifications_commutative, in which case multiple commands can update the same shard concurrently.

For example, if your distributed table contains counters and all your DML queries are UPSERTs that add to the counters, then you can safely turn on citus.all_modifications_commutative since addition is commutative:

::

    SET citus.all_modifications_commutative TO on;
    INSERT INTO counters VALUES ('num_purchases', '2016-03-04', 1)
    ON CONFLICT (c_key, c_date) DO UPDATE SET c_value = counters.c_value + 1;

Note that this query also takes an exclusive lock on the row in PostgreSQL, which may also limit the throughput. When storing counters, consider that using INSERT and summing values in a SELECT does not require exclusive locks.

When the replication factor is 1, it is always safe to enable citus.all_modifications_commutative. Citus does not do this automatically yet.

Bulk Copy (100-200k/s)
----------------------

Hash distributed tables support `COPY <http://www.postgresql.org/docs/current/static/sql-copy.html>`_ from the Citus master for bulk ingestion, which can achieve much higher ingestion rates than regular INSERT statements.

COPY can be used to load data directly from an application using COPY .. FROM STDIN, or from a file on the server or program executed on the server.

::

    COPY counters FROM STDIN WTIH (FORMAT CSV);

In psql, the \\COPY command can be used to load data from the local machine. The \\COPY command actually sends a COPY .. FROM STDIN command to the server before sending the local data, as would an application that loads data directly.

::

    psql -c "\COPY counters FROM 'counters-20160304.csv' (FORMAT CSV)"


A very powerful feature of COPY for hash distributed tables is that it asynchronously copies data to the workers over many parallel connections, one for each shard placement. This means that data can be ingested using multiple workers and multiple cores in parallel. Especially when there are expensive indexes such as a GIN, this can lead to major performance boosts over ingesting into a regular PostgreSQL table.

.. note::

    To avoid opening too many connections to the workers. We recommend only running only one COPY command on a hash distributed table at a time. In practice, running more than two at a time rarely results in performance benefits. An exception is when all the data in the ingested file has a specific partition key value, which goes into a single shard. COPY will only open connections to shards when necessary.

Masterless Citus (50k/s-500k/s)
-------------------------------

.. note::

    This section is currently experimental and not a guide to setup masterless clusters in production. We are working on providing official support for masterless clusters including replication and automated fail-over solutions. Please contact us at engage@citusdata.com if your use-case requires multiple masters.

It is technically possible to create the distributed table on every node in the cluster. The big advantage is that all  queries on distributed tables can be performed at a very high rate by spreading the queries across the workers. In this case, the replication factor should always be 1 to ensure consistency, which causes data to become unavailable when a node goes down. All nodes should have a hot standby and automated fail-over to ensure high availability.

To allow DML commands on the distribute table from any node, first create a distributed table on both the master and the workers:

::

    CREATE TABLE data (key text, value text);
    SELECT master_create_distributed_table('data','key','hash');

Then on the master, create shards for the distributed table with a replication factor of 1.

::

    -- Create 128 shards with a single replica on the workers
    SELECT master_create_worker_shards('data', 128, 1);

Finally, you need to copy and convert the shard metadata from the master to the workers. The logicalrelid column in pg_dist_shard may differ per node. If you have the dblink extension installed, then you can run the following commands on the workers to get the metadata from master-node.

::

    INSERT INTO pg_dist_shard SELECT * FROM
    dblink('host=master-node port=5432',
           'SELECT logicalrelid::regclass,shardid,shardstorage,shardalias,shardminvalue,shardmaxvalue FROM pg_dist_shard')
    AS (logicalrelid regclass, shardid bigint, shardstorage char, shardalias text, shardminvalue text, shardmaxvalue text);

    INSERT INTO pg_dist_shard_placement SELECT * FROM
    dblink('host=master-node port=5432',
           'SELECT * FROM pg_dist_shard_placement')
    AS (shardid bigint, shardstate int, shardlength bigint, nodename text, nodeport int);

After these commands, you can connect to any node and perform both SELECT and DML commands on the distributed table. However, DDL commands won't be supported.

Append Distributed Tables
$$$$$$$$$$$$$$$$$$$$$$$$$

If your use-case does not require real-time ingests, then using append distributed tables will give you the highest ingest rates. This approach is more suitable for use-cases which use time-series data and where the database can be a few minutes or more behind.

Master Node Bulk Ingestion (100k/s-200k/s)
------------------------------------------

To ingest data into an append distributed table, you can use the `COPY <http://www.postgresql.org/docs/9.5/static/sql-copy.html>`_ command, which will create a new shard out of the data you ingest. COPY can break up files larger than the configured citus.shard_max_size into multiple shards. COPY for append distributed tables only opens connections for the new shards, which means it behaves a bit differently than COPY for hash distributed tables, which may open connections for all shards. A COPY for append distributed tables command does not ingest rows in parallel over many connections, but it is safe to run many commands in parallel.

::

    -- Set up the events table
    CREATE TABLE events (time timestamp, data jsonb);
    SELECT master_create_distributed_table('events', 'time', 'append');
    
    -- Add data into a new staging table
    \COPY events FROM 'path-to-csv-file' WITH CSV

COPY creates new shards every time it is used, which allows many files to be ingested simultaneously, but may cause issues if queries end up involving thousands of shards. An alternative way to ingest data is to append it to existing shards using the master_append_table_to_shard function. To use master_append_table_to_shard, the data needs to be loaded into a staging table and some custom logic to select an appropriate shard is required.

::

    -- Prepare a staging table
    CREATE TABLE stage_1 (LIKE events);
    \COPY stage_1 FROM 'path-to-csv-file WITH CSV

    -- In a separate transaction, append the staging table
    SELECT master_append_table_to_shard(select_events_shard(), 'stage_1', 'master-node', 5432);

An example of a shard selection function is given below. It appends to a shard until its size is greater than 1GB and then creates a new one, which has the drawback of only allowing one append at a time, but the advantage of bounding shard sizes.

::

    CREATE OR REPLACE FUNCTION select_events_shard() RETURNS bigint AS $$
    DECLARE
      shard_id bigint;
    BEGIN
      SELECT shardid INTO shard_id
      FROM pg_dist_shard JOIN pg_dist_shard_placement USING (shardid)
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
----------------------------------------

For very high data ingestion rates, data can be staged via the workers. This method scales out horizontally and provides the highest ingestion rates, but can be more complex to use. Hence, we recommend trying this method only if your data ingestion rates cannot be addressed by the previously described methods.

Append distributed tables support COPY via the worker, by specifying the address of the master in a master_host option, and optionally a master_port option (defaults to 5432). COPY via the workers has the same general properties as COPY via the master, except the initial parsing is not bottlenecked on the master.

::

    psql -h worker-node-1 -c "\COPY events FROM 'data.csv' WITH (FORMAT CSV, MASTER_HOST 'master-node')"


An alternative to using COPY is to create a staging table and use standard SQL clients to append it to the distributed table, which is similar to staging data via the master. An example of staging a file via a worker using psql is as follows:

::

    stage_table=$(psql -tA -h worker-node-1 -c "SELECT 'stage_'||nextval('stage_id_sequence')")
    psql -h worker-node-1 -c "CREATE TABLE $stage_table (time timestamp, data jsonb)"
    psql -h worker-node-1 -c "\COPY $stage_table FROM 'data.csv' WITH CSV"
    psql -h master-node -c "SELECT master_append_table_to_shard(choose_underutilized_shard(), '$stage_table', 'worker-node-1', 5432)"
    psql -h worker-node-1 -c "DROP TABLE $stage_table"
    
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
      FROM pg_dist_shard JOIN pg_dist_shard_placement USING (shardid)
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
    SELECT master_create_distributed_table('github_events', 'created_at', 'append');


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
