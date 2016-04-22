.. _query_performance:

Query Performance
#################


CitusDB parallelizes incoming queries by breaking the incoming SQL query into multiple fragment queries ("tasks") which run independently on the worker node shards in parallel. This allows CitusDB to utilize the processing power of all the nodes in the cluster and also of individual cores on each node for each query. Due to this parallelization, users can get performance which is cumulative of the computing power of all of the cores in the cluster leading to a dramatic decrease in query processing times versus PostgreSQL on a single server.

CitusDB employs a two stage optimizer when planning SQL queries. The first phase involves converting the SQL queries into their commutative and associative form so that they can be pushed down and run on the worker nodes in parallel. As discussed above, choosing the right distribution column and distribution method allows the distributed query planner to apply several optimizations to the queries. This can have a significant impact on query performance due to reduced network I/O.

CitusDB’s distributed executor then takes these individual query fragments and sends them to worker nodes. There are several aspects of both the distributed planner and the executor which can be tuned in order to improve performance. When these individual query fragments are sent to the worker nodes, the second phase of query optimization kicks in. The worker nodes are simply running extended PostgreSQL servers and they apply PostgreSQL's standard planning and execution logic to run these fragment SQL queries. Therefore, any optimization that helps PostgreSQL also helps CitusDB. PostgreSQL by default comes with conservative resource settings; and therefore optimizing these configuration settings can improve query times significantly.

We discuss the relevant performance tuning steps in the :ref:`performance_tuning` section of the documentation.
