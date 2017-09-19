.. _production_sizing:

Production Sizing
$$$$$$$$$$$$$$$$$

This section explores configuration settings for running a cluster in production.

.. _prod_shard_count:

Shard Count
===========

The number of nodes in a cluster is easy to change (see :ref:`scaling_out_cluster`), but the number of shards to distribute among those nodes is more difficult to change after cluster creation. Choosing the shard count is a balance between the flexibility of having more shards, and the overhead for query planning and execution across them.

The optimal choice varies depending on your access patterns for the data. For instance, in the :ref:`mt_blurb` use-case we recommend choosing between **32 - 128 shards**.  For smaller workloads say <100GB, you could start with 32 shards and for larger workloads you could choose 64 or 128. This means that you have the leeway to scale from 32 to 128 worker machines.

In the :ref:`rt_blurb` use-case, shard count should be related to the total number of cores on the workers. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. We typically recommend creating a high number of initial shards, e.g. **2x or 4x the number of current CPU cores**. This allows for future scaling if you add more workers and CPU cores.

.. _prod_size:

Initial Hardware Size
=====================

The size of a cluster, in terms of number of nodes and their hardware capacity, is easy to change. (:ref:`Scaling <cloud_scaling>` on Citus Cloud is especially easy.) However you still need to choose an initial size for a new cluster. Here are some tips for a reasonable initial cluster size.

Multi-Tenant SaaS Use-Case
--------------------------

For those migrating to Citus from an existing single-node database instance, we recommend choosing a cluster where the number of worker cores and RAM in total equals that of the original instance. In such scenarios we have seen 2-3x performance improvements because sharding improves resource utilization, allowing smaller indices etc.

The coordinator node needs less memory than workers, so you can choose a compute-optimized machine for running the coordinator. The number of cores required depends on your existing workload (write/read throughput). By default in Citus Cloud the workers use Amazon EC2 instance type R4S, and the coordinator uses C4S.

Real-Time Analytics Use-Case
----------------------------

**Total cores:** when working data fits in RAM, you can expect a linear performance improvement on Citus proportional to the number of worker cores. To determine the right number of cores for your needs, consider the current latency for queries in your single-node database and the required latency in Citus. Divide current latency by desired latency, and round the result.

**Worker RAM:** the best case would be providing enough memory that the majority of the working set fits in memory. The type of queries your application uses affect memory requirements. You can run :code:`EXPLAIN ANALYZE` on a query to determine how much memory it requires.
