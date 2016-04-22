.. _table_distribution_shards:

Table Distribution and Shards
#############################

The first step while creating a CitusDB table is choosing the right distribution column and distribution method. CitusDB supports both append and hash based distribution; and both are better suited to certain use cases. Also, choosing the right distribution column helps CitusDB to push down several operations directly to the worker shards and prune away unrelated shards which lead to significant query speedups. We discuss briefly about choosing the right distribution column and method below.

Typically, users should pick that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, CitusDB uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then CitusDB executes the join only between those shards which have matching / overlapping distribution column ranges. All these shard joins can be executed in parallel on the worker nodes and hence are more efficient.

In addition, CitusDB can push down several operations directly to the worker shards if they are based on the distribution column. This greatly reduces both the amount of computation on each node and the network bandwidth involved in transferring data across nodes.

For distribution methods, CitusDB supports both append and hash distribution. Append based distribution is more suited to append-only use cases. This typically includes event based data which arrives in a time-ordered series. Users then distribute their largest tables by time, and batch load their events into CitusDB in intervals of N minutes. This data model can be applied to a number of time series use cases; for example, each line in a website's log file, machine activity logs or aggregated website events. In this distribution method, CitusDB stores min / max ranges of the partition column in each shard, which allows for more efficient range queries on the partition column.

Hash based distribution is more suited to cases where users want to do real-time inserts along with analytics on their data or want to distribute by a non-ordered column (eg. user id). This data model is relevant for real-time analytics use cases; for example, actions in a mobile application, user website events, or social media analytics. This distribution method allows users to perform co-located joins and efficiently run queries involving equality based filters on the distribution column.

Once you choose the right distribution method and column, you can then proceed
to the next step, which is tuning single node performance.
