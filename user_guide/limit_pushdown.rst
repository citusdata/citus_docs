.. _limit_pushdown:

Limit Pushdown
#####################

CitusDB also pushes down the limit clauses to the shards on the worker nodes wherever possible to minimize the amount of data transferred across network.

However, in some cases, SELECT queries with LIMIT clauses may need to fetch all rows from each shard to generate exact results. For example, if the query requires ordering by the aggregate column, it would need results of that column from all shards to determine the final aggregate value. This reduces performance of the LIMIT clause due to high volume of network data transfer. In such cases, and where an approximation would produce meaningful results, CitusDB provides an option for network efficient approximate LIMIT clauses.

LIMIT approximations are disabled by default and can be enabled by setting the configuration parameter limit_clause_row_fetch_count. On the basis of this configuration value, CitusDB will limit the number of rows returned by each task for master node aggregation. Due to this limit, the final results may be approximate. Increasing this limit will increase the accuracy of the final results, while still providing an upper bound on the number of rows pulled from the worker nodes.

::

    SET limit_clause_row_fetch_count to 10000;
