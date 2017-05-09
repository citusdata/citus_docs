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
    SELECT create_distributed_table('counters', 'c_key');

    -- Enable timing to see reponse times
    \timing on

    -- First INSERT requires connection set-up, second will be faster
    INSERT INTO counters VALUES ('num_purchases', '2016-03-04', 12); -- Time: 10.314 ms
    INSERT INTO counters VALUES ('num_purchases', '2016-03-05', 5); -- Time: 3.132 ms

To reach high throughput rates, remember these techniques:

* Increase CPU cores and memory on the coordinator node. Inserted data must pass through the coordinator, so check whether node resources are maxing out and upgrade the hardware if necessary.
* Ingest with more threads on the client. If you have determined that the coordinator has enough resources, then throughput may be bottlenecked on the client. Try sending using more threads and PostgreSQL connections.
* Avoid closing connections between INSERT statements. This avoids the overhead of connection setup.
* Remember that column size will affect insert speed. Rows with big JSON blobs will take longer than those with small columns like integers.

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

.. _bulk_copy:

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

Masterless Citus (Citus MX) builds on the Citus extension. It gives you the ability to query and write to distributed tables from any node, which allows you to horizontally scale out your write-throughput using PostgreSQL. It also removes the need to interact with a primary node in a Citus cluster for data ingest or queries.

Citus MX is currently available in private beta on Citus Cloud. For more information see :ref:`mx`.
