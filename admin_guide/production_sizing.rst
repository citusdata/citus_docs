.. _production_sizing:

Production Sizing
$$$$$$$$$$$$$$$$$

This section explores configuration settings for running a cluster in production.

Shard Count
===========

The number of nodes in a cluster is easy to change (see :ref:`scaling_out_cluster`), but the number of shards to distribute among those nodes is more difficult to change after cluster creation. Choosing the shard count is a balance between the flexibility of having more shards, and the overhead for query planning and execution across them.

The optimal choice varies depending on your access patterns for the data. For instance, in the :ref:`mt_blurb` use-case we recommend choosing between **32 - 128 shards**.  For smaller workloads say <100GB, you could start with 32 shards and for larger workloads you could choose 64 or 128. This means that you have the leeway to scale from 32 to 128 worker machines.

In the :ref:`rt_blurb` use-case, shard count should be related to the total number of cores on the workers. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. We typically recommend creating a high number of initial shards, e.g. **2x or 4x the number of current CPU cores**. This allows for future scaling if you add more workers and CPU cores.
