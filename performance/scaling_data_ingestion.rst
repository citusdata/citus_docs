.. _scaling_data_ingestion:

Scaling Out Data Ingestion
##########################

Citus lets you scale out data ingestion to very high rates, but there are several trade-offs to consider in terms of application integration, throughput, and latency. In this section, we discuss different approaches to data ingestion, and provide guidelines for expected throughput and latency numbers.

Real-time Insert and Updates
----------------------------

On the Citus coordinator, you can perform INSERT, INSERT .. ON CONFLICT, UPDATE, and DELETE commands directly on distributed tables. When you issue one of these commands, the changes are immediately visible to the user.

When you run an INSERT (or another ingest command), Citus first finds the right shard placements based on the value in the distribution column. Citus then connects to the worker nodes storing the shard placements, and performs an INSERT on each of them. From the perspective of the user, the INSERT takes several milliseconds to process because of the network latency to worker nodes. The Citus coordinator node however can process concurrent INSERTs to reach high throughputs.

Insert Throughput
~~~~~~~~~~~~~~~~~

To measure data ingest rates with Citus, we use a standard tool called pgbench and provide :ref:`repeatable benchmarking steps <citus_write_throughput_benchmark>`.

We also used these steps to run pgbench across different Citus Cloud formations on AWS and observed the following ingest rates for transactional INSERT statements. For these benchmark results, we used the default configuration for Citus Cloud formations, and set pgbench's concurrent thread count to 64 and client count to 256. We didn't apply any optimizations to improve performance numbers; and you can get higher ingest ratios by tuning your database setup.

+---------------------+-------------------------+---------------+----------------------+
| Coordinator Node    | Worker Nodes            | Latency (ms)  | Transactions per sec |
+=====================+=========================+===============+======================+
| 2 cores - 7.5GB RAM | 2 * (1 core - 15GB RAM) |          28.5 |                9,000 |
+---------------------+-------------------------+---------------+----------------------+
| 4 cores -  15GB RAM | 2 * (1 core - 15GB RAM) |          15.3 |               16,600 |
+---------------------+-------------------------+---------------+----------------------+
| 8 cores -  30GB RAM | 2 * (1 core - 15GB RAM) |          15.2 |               16,700 |
+---------------------+-------------------------+---------------+----------------------+
| 8 cores -  30GB RAM | 4 * (1 core - 15GB RAM) |           8.6 |               29,600 |
+---------------------+-------------------------+---------------+----------------------+

We have three observations that follow from these benchmark numbers. First, the top row shows performance numbers for an entry level Citus cluster with one c4.xlarge (two physical cores) as the coordinator and two r4.large (one physical core each) as worker nodes. This basic cluster can deliver 9K INSERTs per second, or 775 million transactional INSERT statements per day.

Second, a more powerful Citus cluster that has about four times the CPU capacity can deliver 30K INSERTs per second, or 2.75 billion INSERT statements per day.

Third, across all data ingest benchmarks, the network latency combined with the number of concurrent connections PostgreSQL can efficiently handle, becomes the  performance bottleneck. In a production environment with hundreds of tables and indexes, this bottleneck will likely shift to a different resource.

Update Througput
~~~~~~~~~~~~~~~~

To measure UPDATE throughputs with Citus, we used the :ref:`same benchmarking steps <citus_update_throughput_benchmark>` and ran pgbench across different Citus Cloud formations on AWS.

+---------------------+-------------------------+---------------+----------------------+
| Coordinator Node    | Worker Nodes            | Latency (ms)  | Transactions per sec |
+=====================+=========================+===============+======================+
| 2 cores - 7.5GB RAM | 2 * (1 core - 15GB RAM) |          25.0 |               10,200 |
+---------------------+-------------------------+---------------+----------------------+
| 4 cores -  15GB RAM | 2 * (1 core - 15GB RAM) |          19.6 |               13,000 |
+---------------------+-------------------------+---------------+----------------------+
| 8 cores -  30GB RAM | 2 * (1 core - 15GB RAM) |          20.3 |               12,600 |
+---------------------+-------------------------+---------------+----------------------+
| 8 cores -  30GB RAM | 4 * (1 core - 15GB RAM) |          10.7 |               23,900 |
+---------------------+-------------------------+---------------+----------------------+

These benchmark numbers show that Citus's UPDATE throughput is slightly lower than those of INSERTs. This is because pgbench creates a primary key index for UPDATE statements and an UPDATE incurs more work on the worker nodes. It's also worth noting two additional differences between INSERT and UPDATEs.

First, UPDATE statements cause bloat in the database and VACUUM needs to run regularly to clean up this bloat. In Citus, since VACUUM runs in parallel across worker nodes, your workloads are less likely to be impacted by VACUUM.

Second, these benchmark numbers show UPDATE throughput for standard Citus deployments. If you're on the Citus community edition, using statement-based replication, and you increased the default replication factor to 2, you're going to observe notably lower UPDATE throughputs. For this particular setting, Citus comes with additional configuration (citus.all_modifications_commutative) that may increase UPDATE ratios.

Insert and Update: Throughput Checklist
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When you're running the above pgbench benchmarks on a moderately sized Citus cluster, you can generally expect 10K-50K INSERTs per second. This translates to approximately 1 to 4 billion INSERTs per day. If you aren't observing these throughputs numbers, remember the following checklist:

* Check the network latency between your application and your database. High latencies will impact your write throughput.
* Ingest data using concurrent threads. If the roundtrip latency during an INSERT is 4ms, you can process 250 INSERTs/second over one thread. If you run 100 concurrent threads, you will see your write throughput increase with the number of threads.
* Check whether the nodes in your cluster have CPU or disk bottlenecks. Ingested data passes through the coordinator node, so check whether your coordinator is bottlenecked on CPU.
* Avoid closing connections between INSERT statements. This avoids the overhead of connection setup.
* Remember that column size will affect insert speed. Rows with big JSON blobs will take longer than those with small columns like integers.

Insert and Update: Latency
~~~~~~~~~~~~~~~~~~~~~~~~~~

The benefit of running INSERT or UPDATE commands, compared to issuing bulk COPY commands, is that changes are immediately visible to other queries. When you issue an INSERT or UPDATE command, the Citus coordinator node directly routes this command to related worker node(s). The coordinator node also keeps connections to the workers open within the same session, which means subsequent commands will see lower response times.

::

    -- Set up a distributed table that keeps account history information
    CREATE TABLE pgbench_history (tid int, bid int, aid int, delta int, mtime timestamp);
    SELECT create_distributed_table('pgbench_history', 'aid');

    -- Enable timing to see reponse times
    \timing on

    -- First INSERT requires connection set-up, second will be faster
    INSERT INTO pgbench_history VALUES (10, 1, 10000, -5000, CURRENT_TIMESTAMP); -- Time: 10.314 ms
    INSERT INTO pgbench_history VALUES (10, 1, 22000, 5000, CURRENT_TIMESTAP); -- Time: 3.132 ms

.. _bulk_copy:

Bulk Copy (250K - 2M/s)
-----------------------

Distributed tables support `COPY <http://www.postgresql.org/docs/current/static/sql-copy.html>`_ from the Citus coordinator for bulk ingestion, which can achieve much higher ingestion rates than INSERT statements.

COPY can be used to load data directly from an application using COPY .. FROM STDIN, from a file on the server, or program executed on the server.

::

    COPY pgbench_history FROM STDIN WITH (FORMAT CSV);

In psql, the \\COPY command can be used to load data from the local machine. The \\COPY command actually sends a COPY .. FROM STDIN command to the server before sending the local data, as would an application that loads data directly.

::

    psql -c "\COPY pgbench_history FROM 'pgbench_history-2016-03-04.csv' (FORMAT CSV)"


A powerful feature of COPY for distributed tables is that it asynchronously copies data to the workers over many parallel connections, one for each shard placement. This means that data can be ingested using multiple workers and multiple cores in parallel. Especially when there are expensive indexes such as a GIN, this can lead to major performance boosts over ingesting into a regular PostgreSQL table.

From a throughput standpoint, you can expect data ingest ratios of 250K - 2M rows per second when using COPY. To learn more about COPY performance across different scenarios, please refer to the `following blog post <https://www.citusdata.com/blog/2016/06/15/copy-postgresql-distributed-tables>`_.

.. note::

    To avoid opening too many connections to worker nodes, we recommend running only two COPY commands on a distributed table at a time. In practice, running more than four at a time rarely results in performance benefits. An exception is when all the data in the ingested file has a specific partition key value, which goes into a single shard. COPY will only open connections to shards when necessary.

Masterless Citus (50k/s-500k/s)
-------------------------------

Masterless Citus (Citus MX) builds on the Citus extension. It gives you the ability to query and write to distributed tables from any node, which allows you to horizontally scale out your write-throughput using PostgreSQL. It also removes the need to interact with a primary node in a Citus cluster for data ingest or queries.

Citus MX is currently available in private beta on Citus Cloud. For more information see :ref:`mx`.
