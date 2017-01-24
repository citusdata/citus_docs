.. _distributed_tables:

Picking a Distribution Column
#############################

Every distributed table in Citus has exactly one column which is chosen as the distribution column. This informs the database to maintain statistics about the distribution column in each shard. Citus’s distributed query optimizer then leverages these statistics to determine how best a query should be executed.

Typically, you should choose that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then Citus executes the join only between those shards which have matching / overlapping distribution column ranges. This helps in greatly reducing both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps Citus push down several operations directly to the worker shards, hence reducing network I/O.

.. note::
  Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

The best choice of distribution column varies depending on the use case and queries. Two common scenarios are the multi-tenant B2B application and the realtime analytics dashboard. In the former all tables include a tenant id and are distributed by it. When SQL queries are restricted to accessing data about a single tenant then Citus can execute them within a single shard. Having all data co-located in a shard is efficient and supports all SQL features. However running queries on a single shard limits the ability to parallelize execution.

The other common option, realtime analytics, distributes by another column (such as user id). The queries in this scenario typically request aggregates information from multiple shards. This permits query parallelism but restricts some of the SQL features available, due to the constraints of being a distributed system.
