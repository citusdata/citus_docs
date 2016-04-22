.. _distribution_column:

Distribution Column
###################


Every distributed table in CitusDB has exactly one column which is chosen as the distribution column. This informs the database to maintain statistics about the distribution column in each shard. CitusDB’s distributed query optimizer then leverages these distribution column ranges to determine how best a query should be executed.

Typically, users should choose that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, CitusDB uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then CitusDB executes the join only between those shards which have matching / overlapping distribution column ranges. This helps in greatly reducing both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps CitusDB to push down several operations directly to the worker shards, hence reducing network I/O.

Note: CitusDB also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

The best option for the distribution column varies depending on the use case and the queries. In general, we find two common patterns: (1) **distributing by time** (timestamp, review date, order date), and (2) **distributing by identifier** (user id, order id, application id). Typically, data arrives in a time-ordered series. So, if your use case works well with batch loading, it is easiest to distribute your largest tables by time, and load it into CitusDB in intervals of N minutes. In some cases, it might be worth distributing your incoming data by another key (e.g. user id, application id) and CitusDB will route your rows to the correct shards when they arrive. This can be beneficial when most of your queries involve a filter or joins on user id or order id.
