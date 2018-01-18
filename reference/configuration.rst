.. _configuration:

Configuration Reference
#######################

There are various configuration parameters that affect the behaviour of Citus. These include both standard PostgreSQL parameters and Citus specific parameters. To learn more about PostgreSQL configuration parameters, you can visit the `run time configuration <http://www.postgresql.org/docs/current/static/runtime-config.html>`_ section of PostgreSQL documentation.

The rest of this reference aims at discussing Citus specific configuration parameters. These parameters can be set similar to PostgreSQL parameters by modifying postgresql.conf or `by using the SET command <http://www.postgresql.org/docs/current/static/config-setting.html>`_.

General configuration
---------------------------------------

citus.max_worker_nodes_tracked (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus tracks worker nodes' locations and their membership in a shared hash table on the coordinator node. This configuration value limits the size of the hash table, and consequently the number of worker nodes that can be tracked. The default for this setting is 2048. This parameter can only be set at server start and is effective on the coordinator node.

citus.use_secondary_nodes (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the policy to use when choosing nodes for SELECT queries. If this
is set to 'always', then the planner will query only nodes which are
marked as 'secondary' noderole in :ref:`pg_dist_node <pg_dist_node>`.

The supported values for this enum are:

* **never:** (default) All reads happen on primary nodes.

* **always:** Reads run against secondary nodes instead, and insert/update statements are disabled.

citus.cluster_name (text)
$$$$$$$$$$$$$$$$$$$$$$$$$

Informs the coordinator node planner which cluster it coordinates. Once
cluster_name is set, the planner will query worker nodes in that cluster alone.

.. _enable_version_checks:

citus.enable_version_checks (bool)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Upgrading Citus version requires a server restart (to pick up the new
shared-library), as well as running an ALTER EXTENSION UPDATE command. The
failure to execute both steps could potentially cause errors or crashes. Citus
thus validates the version of the code and that of the extension match, and
errors out if they don't.

This value defaults to true, and is effective on the coordinator. In rare cases,
complex upgrade processes may require setting this parameter to false, thus
disabling the check.

citus.log_distributed_deadlock_detection (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Whether to log distributed deadlock detection related processing in the server log. It defaults to false.

citus.distributed_deadlock_detection_factor (floating point)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the time to wait before checking for distributed deadlocks. In particular the time to wait will be this value multiplied with PostgreSQL's deadlock_timeout setting. If the detection factor is set to its maximum value of 1000, then distributed deadlock detection is disabled. The default value is 2.

citus.max_task_string_size (integer)
------------------------------------

Sets the maximum size (in bytes) of a worker task call string. Changing this value requires a server restart, it cannot be changed at runtime.

Active worker tasks are tracked in a shared hash table on the master node. This configuration value limits the maximum size of an individual worker task, and affects the size of pre-allocated shared memory.

Minimum: 8192, Maximum 65536, Default 12288

Data Loading
---------------------------

citus.multi_shard_commit_protocol (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the commit protocol to use when performing COPY on a hash distributed table. On each individual shard placement, the COPY is performed in a transaction block to ensure that no data is ingested if an error occurs during the COPY. However, there is a particular failure case in which the COPY succeeds on all placements, but a (hardware) failure occurs before all transactions commit. This parameter can be used to prevent data loss in that case by choosing between the following commit protocols: 

* **1pc:** The transactions in which COPY is performed on the shard placements is committed in a single round. Data may be lost if a commit fails after COPY succeeds on all placements (rare). This is the default protocol.

* **2pc:** The transactions in which COPY is performed on the shard placements are first prepared using PostgreSQL's `two-phase commit <http://www.postgresql.org/docs/current/static/sql-prepare-transaction.html>`_ and then committed. Failed commits can be manually recovered or aborted using COMMIT PREPARED or ROLLBACK PREPARED, respectively. When using 2pc, `max_prepared_transactions <http://www.postgresql.org/docs/current/static/runtime-config-resource.html>`_ should be increased on all the workers, typically to the same value as max_connections.

.. _replication_factor:

citus.shard_replication_factor (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the replication factor for shards i.e. the number of nodes on which shards will be placed and defaults to 1. This parameter can be set at run-time and is effective on the coordinator.
The ideal value for this parameter depends on the size of the cluster and rate of node failure. For example, you may want to increase this replication factor if you run large clusters and observe node failures on a more frequent basis.

citus.shard_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the shard count for hash-partitioned tables and defaults to 32. This value is used by
the :ref:`create_distributed_table <create_distributed_table>` UDF when creating
hash-partitioned tables. This parameter can be set at run-time and is effective on the coordinator. 

citus.shard_max_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the maximum size to which a shard will grow before it gets split and defaults to 1GB. When the source file's size (which is used for staging) for one shard exceeds this configuration value, the database ensures that a new shard gets created. This parameter can be set at run-time and is effective on the coordinator.

.. Comment out this configuration as currently COPY only support random
   placement policy.
.. citus.shard_placement_policy (enum)
   $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

   Sets the policy to use when choosing nodes for placing newly created shards. When using the \\copy command, the coordinator needs to choose the worker nodes on which it will place the new shards. This configuration value is applicable on the coordinator and specifies the policy to use for selecting these nodes. The supported values for this parameter are :-

   * **round-robin:** The round robin policy is the default and aims to distribute shards evenly across the cluster by selecting nodes in a round-robin fashion. This allows you to copy from any node including the coordinator node.

   * **local-node-first:** The local node first policy places the first replica of the shard on the client node from which the \\copy command is being run. As the coordinator node does not store any data, the policy requires that the command be run from a worker node. As the first replica is always placed locally, it provides better shard placement guarantees.

Planner Configuration
------------------------------------------------

citus.large_table_shard_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the shard count threshold over which a table is considered large and defaults to 4. This criteria is then used in picking a table join order during distributed query planning. This value can be set at run-time and is effective on the coordinator.

citus.limit_clause_row_fetch_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the number of rows to fetch per task for limit clause optimization. In some cases, select queries with limit clauses may need to fetch all rows from each task to generate results. In those cases, and where an approximation would produce meaningful results, this configuration value sets the number of rows to fetch from each shard. Limit approximations are disabled by default and this parameter is set to -1. This value can be set at run-time and is effective on the coordinator.

citus.count_distinct_error_rate (floating point)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus can calculate count(distinct) approximates using the postgresql-hll extension. This configuration entry sets the desired error rate when calculating count(distinct). 0.0, which is the default, disables approximations for count(distinct); and 1.0 provides no guarantees about the accuracy of results. We recommend setting this parameter to 0.005 for best results. This value can be set at run-time and is effective on the coordinator.

citus.task_assignment_policy (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the policy to use when assigning tasks to workers. The coordinator assigns tasks to workers based on shard locations. This configuration value specifies the policy to use when making these assignments. Currently, there are three possible task assignment policies which can be used.

* **greedy:** The greedy policy is the default and aims to evenly distribute tasks across workers.

* **round-robin:** The round-robin policy assigns tasks to workers in a round-robin fashion alternating between different replicas. This enables much better cluster utilization when the shard count for a table is low compared to the number of workers.

* **first-replica:** The first-replica policy assigns tasks on the basis of the insertion order of placements (replicas) for the shards. In other words, the fragment query for a shard is simply assigned to the worker which has the first replica of that shard. This method allows you to have strong guarantees about which shards will be used on which nodes (i.e. stronger memory residency guarantees).

This parameter can be set at run-time and is effective on the coordinator.

Intermediate Data Transfer
-------------------------------------------------------------------

citus.binary_worker_copy_format (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Use the binary copy format to transfer intermediate data between workers. During large table joins, Citus may have to dynamically repartition and shuffle data between different workers. By default, this data is transferred in text format. Enabling this parameter instructs the database to use PostgreSQL’s binary serialization format to transfer this data. This parameter is effective on the workers and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for this change to take effect.


citus.binary_master_copy_format (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Use the binary copy format to transfer data between coordinator and the workers. When running distributed queries, the workers transfer their intermediate results to the coordinator for final aggregation. By default, this data is transferred in text format. Enabling this parameter instructs the database to use PostgreSQL’s binary serialization format to transfer this data. This parameter can be set at runtime and is effective on the coordinator.

citus.max_intermediate_result_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The maximum size in KB of intermediate results for CTEs and complex subqueries. The default is 1GB, and a value of -1 means no limit. Queries exceeding the limit will be canceled and produce an error message.

DDL
-------------------------------------------------------------------

.. _enable_ddl_prop:

citus.enable_ddl_propagation (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Specifies whether to automatically propagate DDL changes from the coordinator to all workers. The default value is true. Because some schema changes require an access exclusive lock on tables and because the automatic propagation applies to all workers sequentially it can make a Citus cluter temporarily less responsive. You may choose to disable this setting and propagate changes manually.

.. note::

  For a list of DDL propagation support, see :ref:`ddl_prop_support`.

Executor Configuration
------------------------------------------------------------

citus.all_modifications_commutative
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus enforces commutativity rules and acquires appropriate locks for modify operations in order to guarantee correctness of behavior. For example, it assumes that an INSERT statement commutes with another INSERT statement, but not with an UPDATE or DELETE statement. Similarly, it assumes that an UPDATE or DELETE statement does not commute with another UPDATE or DELETE statement. This means that UPDATEs and DELETEs require Citus to acquire stronger locks.

If you have UPDATE statements that are commutative with your INSERTs or other UPDATEs, then you can relax these commutativity assumptions by setting this parameter to true. When this parameter is set to true, all commands are considered commutative and claim a shared lock, which can improve overall throughput. This parameter can be set at runtime and is effective on the coordinator.

citus.remote_task_check_interval (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the frequency at which Citus checks for statuses of jobs managed by the task tracker executor. It defaults to 10ms. The coordinator assigns tasks to workers, and then regularly checks with them about each task's progress. This configuration value sets the time interval between two consequent checks. This parameter is effective on the coordinator and can be set at runtime.

citus.task_executor_type (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus has two executor types for running distributed SELECT queries. The desired executor can be selected by setting this configuration parameter. The accepted values for this parameter are:

* **real-time:** The real-time executor is the default executor and is optimal when you require fast responses to queries that involve aggregations and co-located joins spanning across multiple shards.

* **task-tracker:** The task-tracker executor is well suited for long running, complex queries which require shuffling of data across worker nodes and efficient resource management.

This parameter can be set at run-time and is effective on the coordinator. For more details about the executors, you can visit the :ref:`distributed_query_executor` section of our documentation.

.. _multi_task_logging:

citus.multi_task_query_log_level (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets a log-level for any query which generates more than one task (i.e. which
hits more than one shard). This is useful during a multi-tenant application
migration, as you can choose to error or warn for such queries, to find them and
add a tenant_id filter to them. This parameter can be set at runtime and is
effective on the coordinator. The default value for this parameter is 'off'.

The supported values for this enum are:

* **off:** Turn off logging any queries which generate multiple tasks (i.e. span multiple shards)

* **debug:** Logs statement at DEBUG severity level.

* **log:** Logs statement at LOG severity level.

* **notice:** Logs statement at NOTICE severity level.

* **warning:** Logs statement at WARNING severity level.

* **error:** Logs statement at ERROR severity level.

Note that it may be useful to use :code:`error` or :code:`warning` during testing, and a
lower log-level like :code:`notice` or :code:`log` during actual production deployment.

Real-time executor configuration
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The Citus query planner first prunes away the shards unrelated to a query and then hands the plan over to the real-time executor. For executing the plan, the real-time executor opens one connection and uses two file descriptors per unpruned shard. If the query hits a high number of shards, then the executor may need to open more connections than max_connections or use more file descriptors than max_files_per_process.

In such cases, the real-time executor will begin throttling tasks to prevent overwhelming the worker resources. Since this throttling can reduce query performance, the real-time executor will issue an appropriate warning suggesting that increasing these parameters might be required to maintain the desired performance. These parameters are discussed in brief below.

max_connections (integer)
************************************************

Sets the maximum number of concurrent connections to the database server. The default is typically 100 connections, but might be less if your kernel settings will not support it (as determined during initdb). The real time executor maintains an open connection for each shard to which it sends queries. Increasing this configuration parameter will allow the executor to have more concurrent connections and hence handle more shards in parallel. This parameter has to be changed on the workers as well as the coordinator, and can be done only during server start.

max_files_per_process (integer)
*******************************************************

Sets the maximum number of simultaneously open files for each server process and defaults to 1000. The real-time executor requires two file descriptors for each shard it sends queries to. Increasing this configuration parameter will allow the executor to have more open file descriptors, and hence handle more shards in parallel. This change has to be made on the workers as well as the coordinator, and can be done only during server start.

.. note::
  Along with max_files_per_process, one may also have to increase the kernel limit for open file descriptors per process using the ulimit command.

citus.enable_repartition_joins (boolean)
****************************************

Ordinarily, attempting to perform :ref:`repartition_joins` with the real-time executor will fail with an error message. However setting ``citus.enable_repartition_joins`` to true allows Citus to temporarily switch into the task-tracker executor to perform the join. The default value is false.

Task tracker executor configuration
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

citus.task_tracker_delay (integer)
**************************************************

This sets the task tracker sleep time between task management rounds and defaults to 200ms. The task tracker process wakes up regularly, walks over all tasks assigned to it, and schedules and executes these tasks. Then, the task tracker sleeps for a time period before walking over these tasks again. This configuration value determines the length of that sleeping period. This parameter is effective on the workers and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for the change to take effect.

This parameter can be decreased to trim the delay caused due to the task tracker executor by reducing the time gap between the management rounds. This is useful in cases when the shard queries are very short and hence update their status very regularly. 

citus.max_tracked_tasks_per_node (integer)
****************************************************************

Sets the maximum number of tracked tasks per node and defaults to 1024. This configuration value limits the size of the hash table which is used for tracking assigned tasks, and therefore the maximum number of tasks that can be tracked at any given time. This value can be set only at server start time and is effective on the workers.

This parameter would need to be increased if you want each worker node to be able to track more tasks. If this value is lower than what is required, Citus errors out on the worker node saying it is out of shared memory and also gives a hint indicating that increasing this parameter may help.

citus.max_assign_task_batch_size (integer)
*******************************************

The task tracker executor on the coordinator synchronously assigns tasks in batches to the deamon on the workers. This parameter sets the maximum number of tasks to assign in a single batch. Choosing a larger batch size allows for faster task assignment. However, if the number of workers is large, then it may take longer for all workers to get tasks. This parameter can be set at runtime and is effective on the coordinator.

citus.max_running_tasks_per_node (integer)
****************************************************************

The task tracker process schedules and executes the tasks assigned to it as appropriate. This configuration value sets the maximum number of tasks to execute concurrently on one node at any given time and defaults to 8. This parameter is effective on the worker nodes and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for the change to take effect.

This configuration entry ensures that you don't have many tasks hitting disk at the same time and helps in avoiding disk I/O contention. If your queries are served from memory or SSDs, you can increase max_running_tasks_per_node without much concern.

citus.partition_buffer_size (integer)
************************************************

Sets the buffer size to use for partition operations and defaults to 8MB. Citus allows for table data to be re-partitioned into multiple files when two large tables are being joined. After this partition buffer fills up, the repartitioned data is flushed into files on disk. This configuration entry can be set at run-time and is effective on the workers.


Explain output
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

citus.explain_all_tasks (boolean)
************************************************

By default, Citus shows the output of a single, arbitrary task when running `EXPLAIN <http://www.postgresql.org/docs/current/static/sql-explain.html>`_ on a distributed query. In most cases, the explain output will be similar across tasks. Occassionally, some of the tasks will be planned differently or have much higher execution times. In those cases, it can be useful to enable this parameter, after which the EXPLAIN output will include all tasks. This may cause the EXPLAIN to take longer.
