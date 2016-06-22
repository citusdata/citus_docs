.. _citus_query_processing:

Citus Query Processing
$$$$$$$$$$$$$$$$$$$$$$$$

A Citus cluster consists of a master instance and multiple worker instances. The data is sharded and replicated on the workers while the master stores metadata about these shards. All queries issued to the cluster are executed via the master. The master partitions the query into smaller query fragments where each query fragment can be run independently on a shard. The master then assigns the query fragments to workers, oversees their execution, merges their results, and returns the final result to the user. The query processing architecture can be described in brief by the diagram below.

.. image:: ../images/citus-high-level-arch.png

Citus’s query processing pipeline involves the two components:

* **Distributed Query Planner and Executor**
* **PostgreSQL Planner and Executor**

We discuss them in greater detail in the subsequent sections.

.. _distributed_query_planner:

Distributed Query Planner
#########################

Citus’s distributed query planner takes in a SQL query and plans it for distributed execution.

For SELECT queries, the planner first creates a plan tree of the input query and transforms it into its commutative and associative form so it can be parallelized. It also applies several optimizations to ensure that the queries are executed in a scalable manner, and that network I/O is minimized.

Next, the planner breaks the query into two parts - the master query which runs on the master and the worker query fragments which run on individual shards on the workers. The planner then assigns these query fragments to the workers such that all their resources are used efficiently. After this step, the distributed query plan is passed on to the distributed executor for execution.

The planning process for key-value lookups on the distribution column or modification queries is slightly different as they hit exactly one shard. Once the planner receives an incoming query, it needs to decide the correct shard to which the query should be routed. To do this, it extracts the distribution column in the incoming row and looks up the metadata to determine the right shard for the query. Then, the planner rewrites the SQL of that command to reference the shard table instead of the original table. This re-written plan is then passed to the distributed executor.

.. _examining_plan:

Examining Distributed Query Plan
##################################

Citus extends the SQL EXPLAIN command to provide information about simple distributed queries, meaning queries that do not contain re-partition jobs. The EXPLAIN output consists of two parts: the distributed query and the master query.

Here is an example of explaining the plan for a query in the :ref:`hash partitioning tutorial <tut_hash>`:

::

  explain SELECT comment FROM wikipedia_changes c, wikipedia_editors e
          WHERE c.editor = e.editor AND e.bot IS true LIMIT 10;

  Distributed Query into pg_merge_job_0005
    Executor: Real-Time
    Task Count: 16
    Tasks Shown: One of 16
    ->  Task
      Node: host=localhost port=9701 dbname=j
      ->  Limit  (cost=0.15..6.87 rows=10 width=32)
        ->  Nested Loop  (cost=0.15..131.12 rows=195 width=32)
          ->  Seq Scan on wikipedia_changes_102024 c  (cost=0.00..13.90 rows=390 width=64)
          ->  Index Scan using wikipedia_editors_editor_key_102008 on wikipedia_editors_102008 e  (cost=0.15..0.29 rows=1 width=32)
            Index Cond: (editor = c.editor)
            Filter: (bot IS TRUE)
  Master Query
    ->  Limit  (cost=0.00..0.00 rows=0 width=0)
      ->  Seq Scan on pg_merge_job_0005  (cost=0.00..0.00 rows=0 width=0)
  (15 rows)

Every shard corresponds to a task. From the above you can see in this case the master query iterates over the merged results of each task. By default one worker task is selected arbitrarily for display. If all workers have a similar hardware configuration and all shards are of similar size then the plan for this task will be representative of the others. If however you want to see the plan of every task individually, set the GUC variable citus.explain_all_tasks to 1.

.. note::

  * A remote EXPLAIN may error out when explaining a broadcast join while the shards for the small table have not yet been fetched. An error message is displayed advising to run the query first.
  * When citus.explain_all_tasks is on, EXPLAIN plans are retrieved sequentially, which may take a long time for EXPLAIN ANALYZE.

.. _distributed_query_executor:

Distributed Query Executor
##########################

Citus’s distributed executors run distributed query plans and handle failures that occur during query execution. The executors connect to the workers, send the assigned tasks to them and oversee their execution. If the executor cannot assign a task to the designated worker or if a task execution fails, then the executor dynamically re-assigns the task to replicas on other workers. The executor processes only the failed query sub-tree, and not the entire query while handling failures.

Citus has two executor types - real time and task tracker. The former is useful for handling simple key-value lookups and INSERT, UPDATE, and DELETE queries, while the task tracker is better suited for larger SELECT queries.

Real-time Executor
-------------------

The real-time executor is the default executor used by Citus. It is well suited for getting fast responses to queries involving filters, aggregations and colocated joins. The real time executor opens one connection per shard to the workers and sends all fragment queries to them. It then fetches the results from each fragment query, merges them, and gives the final results back to the user.

Since the real time executor maintains an open connection for each shard to which it sends queries, it may reach file descriptor / connection limits while dealing with high shard counts. In such cases, the real-time executor throttles on assigning more tasks to workers to avoid overwhelming them with too many tasks. One can typically increase the file descriptor limit on modern operating systems to avoid throttling, and change Citus configuration to use the real-time executor. But, that may not be ideal for efficient resource management while running complex queries. For queries that touch thousands of shards or require large table joins, you can use the task tracker executor.

Furthermore, when the real time executor detects simple INSERT, UPDATE or DELETE queries it assigns the incoming query to the worker which has the target shard. The query is then handled by the worker PostgreSQL server and the results are returned back to the user. In case a modification fails on a shard replica, the executor marks the corresponding shard replica as invalid in order to maintain data consistency.


Task Tracker Executor
----------------------

The task tracker executor is well suited for long running, complex data warehousing queries. This executor opens only one connection per worker, and assigns all fragment queries to a task tracker daemon on the worker. The task tracker daemon then regularly schedules new tasks and sees through their completion. The executor on the master regularly checks with these task trackers to see if their tasks completed.

Each task tracker daemon on the workers also makes sure to execute at most citus.max_running_tasks_per_node concurrently. This concurrency limit helps in avoiding disk I/O contention when queries are not served from memory. The task tracker executor is designed to efficiently handle complex queries which require repartitioning and shuffling intermediate data among workers.

.. _postgresql_planner_executor:

PostgreSQL planner and executor
################################

Once the distributed executor sends the query fragments to the workers, they are processed like regular PostgreSQL queries. The PostgreSQL planner on that worker chooses the most optimal plan for executing that query locally on the corresponding shard table. The PostgreSQL executor then runs that query and returns the query results back to the distributed executor. You can learn more about the PostgreSQL `planner <http://www.postgresql.org/docs/9.5/static/planner-optimizer.html>`_ and `executor <http://www.postgresql.org/docs/9.5/static/executor.html>`_ from the PostgreSQL manual. Finally, the distributed executor passes the results to the master for final aggregation.
