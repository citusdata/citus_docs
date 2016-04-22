.. _distributed_query_executor:

Distributed Query Executor
##########################

CitusDB’s distributed executors run distributed query plans and handle failures that occur during query execution. The executors connect to the worker nodes, send the assigned tasks to them and oversee their execution. If the executor cannot assign a task to the designated worker node or if a task execution fails, then the executor dynamically re-assigns the task to replicas on other worker nodes. The executor processes only the failed query sub-tree, and not the entire query while handling failures.

CitusDB has 3 different executor types - real time, task tracker and routing. The first two are used for SELECT queries while the routing executor is used for handling INSERT, UPDATE, and DELETE queries. We briefly discuss the executors below.

Real-time Executor
-------------------------------

The real-time executor is the default executor used by CitusDB. It is well suited for queries which require quick responses like single key lookups, filters, aggregations and colocated joins. The real time executor opens one connection per shard to the worker nodes and sends all fragment queries to them. It then fetches the results from each fragment query, merges them, and gives them back to the user.

Since the real time executor maintains an open connection for each shard to which it sends queries, it may reach file descriptor / connection limits while dealing with high shard counts. In such cases, the real-time executor throttles on assigning more tasks to worker nodes to avoid overwhelming them too many tasks. One can typically increase the file descriptor limit on modern OSes to avoid throttling, and change CitusDB configuration to use the real-time executor. But, that may not be ideal for efficient resource management while running complex queries. For queries that touch thousands of shards or require large table joins, you can use the task tracker executor.

Task Tracker Executor
------------------------

The task tracker executor is well suited for long running, complex queries. This executor opens only one connection per worker node, and assigns all fragment queries to a task tracker daemon on the worker node. The task tracker daemon then regularly schedules new tasks and sees through their completion. The executor on the master node regularly checks with these task trackers to see if their tasks completed.

Each task tracker daemon on the worker node also makes sure to execute at most max_running_tasks_per_node concurrently. This concurrency limit helps in avoiding disk I/O contention when queries are not served from memory. The task tracker executor is designed to efficiently handle complex queries which require repartitioning and shuffling intermediate data among worker nodes.

Routing Executor
-------------------

The routing executor is used by CitusDB for handling INSERT, UPDATE and DELETE queries. This executor assigns the incoming query to the worker node which have the target shard. The query is then handled by the PostgreSQL server on the worker node. In case a modification fails on a shard replica, the executor marks the corresponding shard replica as invalid in order to maintain data consistency.
