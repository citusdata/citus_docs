.. _scaling_data_ingestion:

Scaling Out Data Ingestion
##########################

Citus lets you scale out data ingestion to very high rates, but there are several trade-offs to consider in terms of the throughput, durability, consistency and latency. In this section, we discuss several approaches to data ingestion and give examples of how to use them.

Real-time Inserts (0-50k/s)
---------------------------

On the Citus master, you can perform INSERT commands directly on hash distributed tables. The advantage of using INSERT is that the new data is immediately visible to SELECT queries, and durably stored on multiple replicas.

When processing an INSERT, Citus first finds the right shard placements based on the value in the distribution column, then it connects to the workers storing the shard placements, and finally performs an INSERT on each of them. From the perspective of the user, the INSERT takes several milliseconds to process because of the round-trips to the workers, but the master can process other INSERTs in other sessions while waiting for a response. The master also keeps connections to the workers open within the same session, which means subsequent queries will see lower response times.

::

    -- Set up a distributed table containing counters
    CREATE TABLE counters (c_key text, c_date date, c_value int, primary key (c_key, c_date));
    SELECT create_distributed_table('counters', 'c_key', 'hash');

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

    COPY counters FROM STDIN WITH (FORMAT CSV);

In psql, the \\COPY command can be used to load data from the local machine. The \\COPY command actually sends a COPY .. FROM STDIN command to the server before sending the local data, as would an application that loads data directly.

::

    psql -c "\COPY counters FROM 'counters-20160304.csv' (FORMAT CSV)"


A very powerful feature of COPY for hash distributed tables is that it asynchronously copies data to the workers over many parallel connections, one for each shard placement. This means that data can be ingested using multiple workers and multiple cores in parallel. Especially when there are expensive indexes such as a GIN, this can lead to major performance boosts over ingesting into a regular PostgreSQL table.

.. note::

    To avoid opening too many connections to the workers. We recommend only running only one COPY command on a hash distributed table at a time. In practice, running more than two at a time rarely results in performance benefits. An exception is when all the data in the ingested file has a specific partition key value, which goes into a single shard. COPY will only open connections to shards when necessary.

Masterless Citus (50k/s-500k/s)
-------------------------------

.. note::

    This section is currently experimental and not a guide to setup masterless clusters in production. We are working on providing official support for masterless clusters including replication and automated fail-over solutions. Please `contact us <https://www.citusdata.com/about/contact_us>`_ if your use-case requires multiple masters.

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
