.. _performance_tuning:

Query Performance Tuning
$$$$$$$$$$$$$$$$$$$$$$$$$$

In this section, we describe how you can tune your Citus cluster to get
maximum performance. We begin by explaining how choosing the
right distribution column and method affect performance. We then describe how
you can first tune your database for high performance on one PostgreSQL server and
then scale it out across all the CPUs in the cluster. In this section, we also discuss
several performance related configuration parameters wherever relevant.

.. _table_distribution_shards:

Table Distribution and Shards
#############################

The first step while creating a distributed table is choosing the right distribution column and distribution method. Citus supports both append and hash based distribution; and both are better suited to certain use cases. Also, choosing the right distribution column helps Citus push down several operations directly to the worker shards and prune away unrelated shards which lead to significant query speedups. We discuss briefly about choosing the right distribution column and method below.

Typically, you should pick that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then Citus executes the join only between those shards which have matching / overlapping distribution column ranges. All these shard joins can be executed in parallel on the workers and hence are more efficient.

In addition, Citus can push down several operations directly to the worker shards if they are based on the distribution column. This greatly reduces both the amount of computation on each node and the network bandwidth involved in transferring data across nodes.

For distribution methods, Citus supports both append and hash distribution. Append based distribution is more suited to append-only use cases. This typically includes event based data which arrives in a time-ordered series. Users then distribute their largest tables by time, and batch load their events into distributed tables in intervals of N minutes. This data model can be applied to a number of time series use cases; for example, each line in a website's log file, machine activity logs or aggregated website events. In this distribution method, Citus stores min / max ranges of the distribution column in each shard, which allows for more efficient range queries on the distribution column.

Hash based distribution is more suited to cases where users want to do real-time inserts along with analytics on their data or want to distribute by a non-ordered column (eg. user id). This data model is relevant for real-time analytics use cases; for example, actions in a mobile application, user website events, or social media analytics. This distribution method allows users to perform co-located joins and efficiently run queries involving equality based filters on the distribution column.

Once you choose the right distribution method and column, you can then proceed to the next step, which is tuning worker node performance.

.. _postgresql_tuning:

PostgreSQL tuning
#################

The Citus master partitions an incoming query into fragment queries, and sends them to the workers for parallel processing. The workers are just extended PostgreSQL servers and they apply PostgreSQL's standard planning and execution logic for these queries. So, the first step in tuning Citus is tuning the PostgreSQL configuration parameters on the workers for high performance.

While adjusting parameters to tune the workers we want fast iterations. To begin the tuning process, create a Citus cluster and load a small portion of your data in it. This will keep operations fast. Once the data is loaded, use the EXPLAIN command on the master node to inspect performance. 

Citus extends the SQL EXPLAIN command to provide information about simple distributed queries, meaning queries that do not contain re-partition jobs. The EXPLAIN output shows how each worker is processing the query and also a little about how the master node is combining all the results.

Here is an example of explaining the plan for a particular query in the :ref:`hash partitioning tutorial <tut_hash>`:

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

This tells you several things. To begin with there are sixteen shards, and we're using the real-time Citus executor setting:

::

  Distributed Query into pg_merge_job_0005
    Executor: Real-Time
    Task Count: 16

Next it picks one of the workers to and shows you more about how the query behaves there. It indicates the host, port, and database so you can connect to the worker directly if desired:

::

    Tasks Shown: One of 16
    ->  Task
      Node: host=localhost port=9701 dbname=j

Distributed EXPLAIN next shows the results of running a normal PostgreSQL EXPLAIN on that worker for the fragment query:

::

      ->  Limit  (cost=0.15..6.87 rows=10 width=32)
        ->  Nested Loop  (cost=0.15..131.12 rows=195 width=32)
          ->  Seq Scan on wikipedia_changes_102024 c  (cost=0.00..13.90 rows=390 width=64)
          ->  Index Scan using wikipedia_editors_editor_key_102008 on wikipedia_editors_102008 e  (cost=0.15..0.29 rows=1 width=32)
            Index Cond: (editor = c.editor)
            Filter: (bot IS TRUE)

At this stage you can connect to the worker to use standard PostgreSQL tuning to optimize query performance. As you make changes try re-running EXPLAIN from the master.

The first set of such optimizations relates to configuration settings. PostgreSQL by default comes with conservative resource settings; and among these settings, shared_buffers and work_mem are probably the most important ones in optimizing read performance. We discuss these parameters in brief below. Apart from them, several other configuration settings impact query performance. These settings are covered in more detail in the `PostgreSQL manual <http://www.postgresql.org/docs/9.5/static/runtime-config.html>`_ and are also discussed in the `PostgreSQL 9.0 High Performance book <http://www.amazon.com/PostgreSQL-High-Performance-Gregory-Smith/dp/184951030X>`_.

shared_buffers defines the amount of memory allocated to the database for caching data, and defaults to 128MB. If you have a worker node with 1GB or more RAM, a reasonable starting value for shared_buffers is 1/4 of the memory in your system. There are some workloads where even larger settings for shared_buffers are effective, but given the way PostgreSQL also relies on the operating system cache, it's unlikely you'll find using more than 25% of RAM to work better than a smaller amount.

If you do a lot of complex sorts, then increasing work_mem allows PostgreSQL to do larger in-memory sorts which will be faster than disk-based equivalents. If you see lot of disk activity on your worker node inspite of having a decent amount of memory, then increasing work_mem to a higher value can be useful. This will help PostgreSQL in choosing more efficient query plans and allow for greater amount of operations to occur in memory.

Other than the above configuration settings, the PostgreSQL query planner relies on statistical information about the contents of tables to generate good plans. These statistics are gathered when ANALYZE is run, which is enabled by default. You can learn more about the PostgreSQL planner and the ANALYZE command in greater detail in the `PostgreSQL documentation <http://www.postgresql.org/docs/9.5/static/sql-analyze.html>`_.

Lastly, you can create indexes on your tables to enhance database performance. Indexes allow the database to find and retrieve specific rows much faster than it could do without an index. To choose which indexes give the best performance, you can run the query with `EXPLAIN <http://www.postgresql.org/docs/9.5/static/sql-explain.html>`_ to view query plans and optimize the slower parts of the query. After an index is created, the system has to keep it synchronized with the table which adds overhead to data manipulation operations. Therefore, indexes that are seldom or never used in queries should be removed.

For write performance, you can use general PostgreSQL configuration tuning to increase INSERT rates. We commonly recommend increasing checkpoint_timeout and max_wal_size settings. Also, depending on the reliability requirements of your application, you can choose to change fsync or synchronous_commit values.

Once you have tuned a worker to your satisfaction you will have to manually apply those changes to the other workers as well. To verify that they are all behaving properly, set this configuration variable on the master:

::

  SET citus.explain_all_tasks = 1;

This will cause EXPLAIN to show the the query plan for all tasks, not just one.

::

  explain SELECT comment FROM wikipedia_changes c, wikipedia_editors e
          WHERE c.editor = e.editor AND e.bot IS true LIMIT 10;

  Distributed Query into pg_merge_job_0003
    Executor: Real-Time
    Task Count: 16
    Tasks Shown: All
    ->  Task
      Node: host=localhost port=9701 dbname=j
      ->  Limit  (cost=0.15..6.87 rows=10 width=32)
        ->  Nested Loop  (cost=0.15..131.12 rows=195 width=32)
          ->  Seq Scan on wikipedia_changes_102024 c  (cost=0.00..13.90 rows=390 width=64)
          ->  Index Scan using wikipedia_editors_editor_key_102008 on wikipedia_editors_102008 e  (cost=0.15..0.29 rows=1 width=32)
            Index Cond: (editor = c.editor)
            Filter: (bot IS TRUE)
    ->  Task
      Node: host=localhost port=9702 dbname=j
      ->  Limit  (cost=0.15..6.87 rows=10 width=32)
        ->  Nested Loop  (cost=0.15..131.12 rows=195 width=32)
          ->  Seq Scan on wikipedia_changes_102025 c  (cost=0.00..13.90 rows=390 width=64)
          ->  Index Scan using wikipedia_editors_editor_key_102009 on wikipedia_editors_102009 e  (cost=0.15..0.29 rows=1 width=32)
            Index Cond: (editor = c.editor)
            Filter: (bot IS TRUE)
    ->  Task
      Node: host=localhost port=9701 dbname=j
      ->  Limit  (cost=1.13..2.36 rows=10 width=74)
        ->  Hash Join  (cost=1.13..8.01 rows=56 width=74)
          Hash Cond: (c.editor = e.editor)
          ->  Seq Scan on wikipedia_changes_102036 c  (cost=0.00..5.69 rows=169 width=83)
          ->  Hash  (cost=1.09..1.09 rows=3 width=12)
            ->  Seq Scan on wikipedia_editors_102020 e  (cost=0.00..1.09 rows=3 width=12)
              Filter: (bot IS TRUE)
    --
    -- ... repeats for all 16 tasks
    --     alternating between workers one and two
    --     (running in this case locally on ports 9701, 9702)
    --
  Master Query
    ->  Limit  (cost=0.00..0.00 rows=0 width=0)
      ->  Seq Scan on pg_merge_job_0003  (cost=0.00..0.00 rows=0 width=0)

Differences in worker execution can be caused by tuning configuration differences, uneven data distribution across shards, or hardware differences between the machines. To get more information about the time it takes the query to run on each shard you can use EXPLAIN ANALYZE.

.. note::

  Note that when citus.explain_all_tasks is on, EXPLAIN plans are retrieved sequentially, which may take a long time for EXPLAIN ANALYZE. Also a remote EXPLAIN may error out when explaining a broadcast join while the shards for the small table have not yet been fetched. An error message is displayed advising to run the query first.

.. _scaling_out_performance:

Scaling Out Performance
#######################

As mentioned, once you have achieved the desired performance for a single shard you can set similar configuration parameters on all your workers. As Citus runs all the fragment queries in parallel across the worker nodes, users can scale out the performance of their queries to be the cumulative of the computing power of all of the CPU cores in the cluster assuming that the data fits in memory.

Users should try to fit as much of their working set in memory as possible to get best performance with Citus. If fitting the entire working set in memory is not feasible, we recommend using SSDs over HDDs as a best practice. This is because HDDs are able to show decent performance when you have sequential reads over contiguous blocks of data, but have significantly lower random read / write performance. In cases where you have a high number of concurrent queries doing random reads and writes, using SSDs can improve query performance by several times as compared to HDDs. Also, if your queries are highly compute intensive, it might be beneficial to choose machines with more powerful CPUs.

To measure the disk space usage of your database objects, you can log into the worker nodes and use `PostgreSQL administration functions <http://www.postgresql.org/docs/9.5/static/functions-admin.html#FUNCTIONS-ADMIN-DBSIZE>`_ for individual shards. The pg_total_relation_size() function can be used to get the total disk space used by a table. You can also use other functions mentioned in the PostgreSQL docs to get more specific size information. On the basis of these statistics for a shard and the shard count, users can compute the hardware requirements for their cluster.

Another factor which affects performance is the number of shards per worker node. Citus partitions an incoming query into its fragment queries which run on individual worker shards. Hence, the degree of parallelism for each query is governed by the number of shards the query hits. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. Another consideration to keep in mind is that Citus will prune away unrelated shards if the query has filters on the distribution column. So, creating more shards than the number of cores might also be beneficial so that you can achieve greater parallelism even after shard pruning.

.. _distributed_query_performance_tuning:

Distributed Query Performance Tuning
######################################

Once you have distributed your data across the cluster, with each worker optimized for best performance, you should be able to see high performance gains on your queries. After this, the final step is to tune a few distributed performance tuning parameters.

Before we discuss the specific configuration parameters, we recommend that you measure query times on your distributed cluster and compare them with the single shard performance. This can be done by enabling \\timing and running the query on the master node and running one of the fragment queries on the worker nodes. This helps in determining the amount of time spent on the worker nodes and the amount of time spent in fetching the data to the master node. Then, you can figure out what the bottleneck is and optimize the database accordingly.

In this section, we discuss the parameters which help optimize the distributed query planner and executors. There are several relevant parameters and we discuss them in two sections:- general and advanced. The general performance tuning section is sufficient for most use-cases and covers all the common configs. The advanced performance tuning section covers parameters which may provide performance gains in specific use cases.

.. _general_performance_tuning:

General
=======

For higher INSERT performance, the factor which impacts insert rates the most is the level of concurrency. You should try to run several concurrent INSERT statements in parallel. This way you can achieve very high insert rates if you have a powerful master node and are able to use all the CPU cores on that node together.

Citus has two executor types for running SELECT queries. The desired executor can be selected by setting the citus.task_executor_type configuration parameter. If your use case mainly requires simple key-value lookups or requires sub-second responses to aggregations and joins, you can choose the real-time executor. On the other hand if there are long running queries which require repartitioning and shuffling of data across the workers, then you can switch to the the task tracker executor.

An important performance tuning parameter in context of SELECT query performance is citus.remote_task_check_interval. The Citus master assigns tasks to workers, and then regularly checks with them about each task's progress. This configuration value sets the time interval between two consequent checks. Setting this parameter to a lower value reduces query times significantly for sub-second queries. For relatively long running queries (which take minutes as opposed to seconds), reducing this parameter might not be ideal as this would make the master contact the workers more often, incurring a higher overhead.

Other than the above, there are two configuration parameters which can be useful in cases where approximations produce meaningful results. These two parameters are citus.limit_clause_row_fetch_count and citus.count_distinct_error_rate. The former sets the number of rows to fetch from each task while calculating limits while the latter sets the desired error rate when calculating approximate distinct counts. You can learn more about the applicability and usage of these parameters in the user guide sections: :ref:`count_distinct` and :ref:`limit_pushdown`.

.. _advanced_performance_tuning:

Advanced
========

In this section, we discuss advanced performance tuning parameters. These parameters are applicable to specific use cases and may not be required for all deployments.

Task Assignment Policy
-------------------------------------

The Citus query planner assigns tasks to the worker nodes based on shard locations. The algorithm used while making these assignments can be chosen by setting the citus.task_assignment_policy configuration parameter. Users can alter this configuration parameter to choose the policy which works best for their use case.

The **greedy** policy aims to distribute tasks evenly across the workers. This policy is the default and works well in most of the cases. The **round-robin** policy assigns tasks to workers in a round-robin fashion alternating between different replicas. This enables much better cluster utilization when the shard count for a table is low compared to the number of workers. The third policy is the **first-replica** policy which assigns tasks on the basis of the insertion order of placements (replicas) for the shards. With this policy, users can be sure of which shards will be accessed on each machine. This helps in providing stronger memory residency guarantees by allowing you to keep your working set in memory and use it for querying.

Intermediate Data Transfer Format
------------------------------------------------

There are two configuration parameters which relate to the format in which intermediate data will be transferred across workers or between workers and the master. Citus by default transfers intermediate query data in the text format. This is generally better as text files typically have smaller sizes than the binary representation. Hence, this leads to lower network and disk I/O while writing and transferring intermediate data.

However, for certain data types like hll or hstore arrays, the cost of serializing and deserializing data is pretty high. In such cases, using binary format for transferring intermediate data can improve query performance due to reduced CPU usage. There are two configuration parameters which can be used to tune this behaviour, citus.binary_master_copy_format and citus.binary_worker_copy_format. Enabling the former uses binary format to transfer intermediate query results from the workers to the master while the latter is useful in queries which require dynamic shuffling of intermediate data between workers.

Real Time Executor
-------------------------------

If you have SELECT queries which require sub-second response times, you should try to use the real-time executor.

The real-time executor opens one connection and uses two file descriptors per unpruned shard (Unrelated shards are pruned away during planning). Due to this, the executor may need to open more connections than max_connections or use more file descriptors than max_files_per_process if the query hits a high number of shards.

In such cases, the real-time executor will begin throttling tasks to prevent overwhelming resources on the workers. Since this throttling can reduce query performance, the real-time executor will issue a warning suggesting that max_connections or max_files_per_process should be increased. On seeing these warnings, you should increase the suggested parameters to maintain the desired query performance.

Task Tracker Executor
-----------------------------------------

If your queries require repartitioning of data or more efficient resource management, you should use the task tracker executor. There are two configuration parameters which can be used to tune the task tracker executor’s performance.

The first one is the citus.task_tracker_delay. The task tracker process wakes up regularly, walks over all tasks assigned to it, and schedules and executes these tasks. This parameter sets the task tracker sleep time between these task management rounds. Reducing this parameter can be useful in cases when the shard queries are short and hence update their status very regularly.

The second parameter is citus.max_running_tasks_per_node. This configuration value sets the maximum number of tasks to execute concurrently on one worker node node at any given time. This configuration entry ensures that you don't have many tasks hitting disk at the same time and helps in avoiding disk I/O contention. If your queries are served from memory or SSDs, you can increase citus.max_running_tasks_per_node without much concern.

With this, we conclude our discussion about performance tuning in Citus. To learn more about the specific configuration parameters discussed in this section, please visit the :ref:`configuration` section of our documentation.

