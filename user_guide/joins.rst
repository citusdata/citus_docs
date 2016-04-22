.. _joins.rst:

Joins
#####

CitusDB supports equi-JOINs between any number of tables irrespective of their size and distribution method. The query planner chooses the optimal join method and join order based on the statistics gathered from the distributed tables. It evaluates several possible join orders and creates a join plan which requires minimum data to be transferred across network.

To determine the best join strategy, CitusDB treats large and small tables differently while executing JOINs. The distributed tables are classified as large and small on the basis of the configuration entry large_table_shard_count (default value: 4). The tables whose shard count exceeds this value are considered as large while the others small. In practice, the fact tables are generally the large tables while the dimension tables are the small tables.

Broadcast joins
------------------------

This join type is used while joining small tables with each other or with a large table. This is a very common use case where users want to join the keys in the fact tables (large table) with their corresponding dimension tables (small tables). CitusDB replicates the small table to all nodes where the large table's shards are present. Then, all the joins are performed locally on the worker nodes in parallel. Subsequent join queries that involve the small table then use these cached shards.

Colocated joins
----------------------------

To join two large tables efficiently, it is advised that you distribute them on the same columns you used to join the tables. In this case, the CitusDB master node knows which shards of the tables might match with shards of the other table by looking at the distribution column metadata. This allows CitusDB to prune away shard pairs which cannot produce matching join keys. The joins between remaining shard pairs are executed in parallel on the worker nodes and then the results are returned to the master.

Note: In order to benefit most from colocated joins, you should hash distribute your tables on the join key and use the same number of shards for both tables. If you do this, each shard will join with exactly one shard of the other table. Also, the shard creation logic will ensure that shards with the same distribution key ranges are on the same worker nodes. This means no data needs to be transferred between the workers, leading to faster joins.

Repartition joins
----------------------------

In some cases, users may need to join two tables on columns other than the distribution column and irrespective of distribution method. For such cases, CitusDB also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases, the best partition method (hash or range) and the table(s) to be partitioned is determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, colocated joins are more efficient than repartition joins as repartition joins require shuffling of data. So, users should try to distribute their tables by the common join keys whenever possible.
