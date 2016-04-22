.. _configuration:

Configuration Reference
#######################

There are various configuration parameters that affect the behaviour of CitusDB. These include both standard PostgreSQL parameters and CitusDB specific parameters. To learn more about PostgreSQL configuration parameters, you can visit the `run time configuration <http://www.postgresql.org/docs/9.4/static/runtime-config.html>`_ section of PostgreSQL documentation.

The rest of this reference aims at discussing CitusDB specific configuration parameters. These parameters can be set similar to PostgreSQL parameters by modifying postgresql.conf or `by using the SET command <http://www.postgresql.org/docs/9.4/static/config-setting.html>`_.

Node configuration
---------------------------------------

pg_worker_list.conf
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The CitusDB master node needs to have information about the worker nodes in the cluster so that it can communicate with them. This information is stored in the pg_worker_list.conf file in the data directory on the master node. To add this information, you need to append the DNS names and port numbers on which the workers are listening to this file. You can then call pg_reload_conf() or restart the master to allow it to refresh its worker membership list.

The example below adds worker-101 and worker-102 as worker nodes in the pg_worker_list.conf file on the master.

::

	vi /opt/citusdb/4.0/data/pg_worker_list.conf
	# HOSTNAME 	[PORT] 	[RACK]
	worker-101
	worker-102

max_worker_nodes_tracked (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

CitusDB tracks worker nodes' locations and their membership in a shared hash table on the master node. This configuration value limits the size of the hash table, and consequently the number of worker nodes that can be tracked. The default for this setting is 2048. This parameter can only be set at server start and is effective on the master node.


Data Loading
---------------------------

shard_replication_factor (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the replication factor for shards i.e. the number of nodes on which shards will be placed and defaults to 2. This parameter can be set at run-time and is effective on the master node.
The ideal value for this parameter depends on the size of the cluster and rate of node failure. For example, you may want to increase this replication factor if you run large clusters and observe node failures on a more frequent basis.

shard_max_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the maximum size to which a shard will grow before it gets split and defaults to 1GB. When the source file's size (which is used for staging) for one shard exceeds this configuration value, the database ensures that a new shard gets created. This parameter can be set at run-time and is effective on the master node.


shard_placement_policy (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the policy to use when choosing nodes for placing newly created shards. When using the \stage command, the master node needs to choose the worker nodes on which it will place the new shards. This configuration value is applicable on the master node and specifies the policy to use for selecting these nodes. The supported values for this parameter are :-

* **round-robin:** The round robin policy is the default and aims to distribute shards evenly across the cluster by selecting nodes in a round-robin fashion. This allows you to stage from any node including the master node.

* **local-node-first:** The local node first policy places the first replica of the shard on the client node from which the \stage command is being run. As the master node does not store any data, the policy requires that the command be run from a worker node. As the first replica is always placed locally, it provides better shard placement guarantees.


Planner Configuration
------------------------------------------------

large_table_shard_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the shard count threshold over which a table is considered large and defaults to 4. This criteria is then used in picking a table join order during distributed query planning. This value can be set at run-time and is effective on the master node.

limit_clause_row_fetch_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the number of rows to fetch per task for limit clause optimization. In some cases, select queries with limit clauses may need to fetch all rows from each task to generate results. In those cases, and where an approximation would produce meaningful results, this configuration value sets the number of rows to fetch from each shard. Limit approximations are disabled by default and this parameter is set to -1. This value can be set at run-time and is effective on the master node.


count_distinct_error_rate (floating point)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

CitusDB calculates count(distinct) approximates using the postgresql-hll extension. This configuration entry sets the desired error rate when calculating count(distinct). 0.0, which is the default, disables approximations for count(distinct); and 1.0 provides no guarantees about the accuracy of results. We recommend setting this parameter to 0.005 for best results. This value can be set at run-time and is effective on the master node.


task_assignment_policy (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the policy to use when assigning tasks to worker nodes. The master node assigns tasks to worker nodes based on shard locations. This configuration value specifies the policy to use when making these assignments. Currently, there are three possible task assignment policies which can be used.

* **greedy:** The greedy policy is the default and aims to evenly distribute tasks across worker nodes.

* **round-robin:** The round-robin policy assigns tasks to worker nodes in a round-robin fashion alternating between different replicas. This enables much better cluster utilization when the shard count for a table is low compared to the number of workers.

* **first-replica:** The first-replica policy assigns tasks on the basis of the insertion order of placements (replicas) for the shards. In other words, the fragment query for a shard is simply assigned to the worker node which has the first replica of that shard. This method allows you to have strong guarantees about which shards will be used on which nodes (i.e. stronger memory residency guarantees).

This parameter can be set at run-time and is effective on the master node.



Intermediate Data Transfer Format
-------------------------------------------------------------------

binary_worker_copy_format (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Use the binary copy format to transfer intermediate data between worker nodes. During large table joins, CitusDB may have to dynamically repartition and shuffle data between different worker nodes. By default, this data is transferred in text format. Enabling this parameter instructs the database to use PostgreSQL’s binary serialization format to transfer this data. This parameter is effective on the worker nodes and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for this change to take effect.


binary_master_copy_format (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Use the binary copy format to transfer data between master node and the workers. When running distributed queries, the worker nodes transfer their intermediate results to the master node for final aggregation. By default, this data is transferred in text format. Enabling this parameter instructs the database to use PostgreSQL’s binary serialization format to transfer this data. This parameter can be set at runtime and is effective on the master node.

Executor Configuration
------------------------------------------------------------

pg_shard.use_citusdb_select_logic (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Informs the database that CitusDB select logic is to be used for a hash partitioned table. Hash partitioned tables in CitusDB are created using pg_shard. By default, pg_shard uses a simple executor which is more suited for single key lookups. Setting this parameter to true allows users to use the CitusDB executor logic for handling complex queries efficiently. This parameter can be set at runtime and it effective on the master node.

remote_task_check_interval (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the frequency at which CitusDB checks for job statuses and defaults to 10ms. The master node assigns tasks to workers nodes, and then regularly checks with them about each task's progress. This configuration value sets the time interval between two consequent checks. This parameter is effective on the master node and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for the change to take effect.


The ideal value of remote_task_check_interval depends on the workload. If your queries take a few seconds on average, then reducing this value makes sense. On the other hand, if an average query over a shard takes minutes as opposed to seconds then reducing this value may not be ideal. This would make the master node contact each worker node more frequently, which is an overhead you may not want to pay in this case.

task_executor_type (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

CitusDB has 2 different executor types for running distributed SELECT queries. The desired executor can be selected by setting this configuration parameter. The accepted values for this parameter are:

* **real-time:** The real-time executor is the default executor and is well suited for queries which require quick responses.

* **task-tracker:** The task-tracker executor is well suited for long running, complex queries and for efficient resource management.

This parameter can be set at run-time and is effective on the master node. For high performance queries requiring sub-second responses, users should try to use the real-time executor as it has a simpler architecture and lower operational overhead. On the other hand, the task tracker executor is well suited for long running, complex queries which require dynamically repartitioning and shuffling data across worker nodes.

For more details about the executors, you can visit the :ref:`distributed_query_executor` section of our documentation.


Real-time executor configuration
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The CitusDB query planner first prunes away the shards unrelated to a query and then hands the plan over to the real-time executor. For executing the plan, the real-time executor opens one connection and uses two file descriptors per unpruned shard. If the query hits a high number of shards, then the executor may need to open more connections than max_connections or use more file descriptors than max_files_per_process.

In such cases, the real-time executor will begin throttling tasks to prevent overwhelming the worker node resources. Since this throttling can reduce query performance, the real-time executor will issue an appropriate warning suggesting that increasing these parameters might be required to maintain the desired performance. These parameters are discussed in brief below.

max_connections (integer)
************************************************

Sets the maximum number of concurrent connections to the database server. The default is typically 100 connections, but might be less if your kernel settings will not support it (as determined during initdb). The real time executor maintains an open connection for each shard to which it sends queries. Increasing this configuration parameter will allow the executor to have more concurrent connections and hence handle more shards in parallel. This parameter has to be changed on the workers as well as the master, and can be done only during server start.

max_files_per_process (integer)
*******************************************************

Sets the maximum number of simultaneously open files for each server process and defaults to 1000. The real-time executor requires two file descriptors for each shard it sends queries to. Increasing this configuration parameter will allow the executor to have more open file descriptors, and hence handle more shards in parallel. This change has to be made on the workers as well as the master, and can be done only during server start.

Note: Along with max_files_per_process, one may also have to increase the kernel limit for open file descriptors per process using the ulimit command.

Task tracker executor configuration
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

task_tracker_active (boolean)
***************************************************

The task tracker background process runs on every worker node, and manages the execution of tasks assigned to it. This configuration entry activates the task tracker and is set to on by default. This parameter can only be set at server start and is effective on both - the master and worker nodes.
This parameter indicates if you want to start the task tracker process or not. If you set this value to off, the task tracker daemon will not start, and you will not be able to use the task-tracker executor type.

task_tracker_delay (integer)
**************************************************

This sets the task tracker sleep time between task management rounds and defaults to 200ms. The task tracker process wakes up regularly, walks over all tasks assigned to it, and schedules and executes these tasks. Then, the task tracker sleeps for a time period before walking over these tasks again. This configuration value determines the length of that sleeping period. This parameter is effective on the worker nodes and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for the change to take effect.

This parameter can be decreased to trim the delay caused due to the task tracker executor by reducing the time gap between the management rounds. This is useful in cases when the shard queries are very short and hence update their status very regularly. 

max_tracked_tasks_per_node (integer)
****************************************************************

Sets the maximum number of tracked tasks per node and defaults to 1024. This configuration value limits the size of the hash table which is used for tracking assigned tasks, and therefore the maximum number of tasks that can be tracked at any given time. This value can be set only at server start time and is effective on the worker nodes.

This parameter would need to be increased if you want each worker node to be able to track more tasks. If this value is lower than what is required, CitusDB errors out on the worker node saying it is out of shared memory and also gives a hint indicating that increasing this parameter may help.

max_running_tasks_per_node (integer)
****************************************************************

The task tracker process schedules and executes the tasks assigned to it as appropriate. This configuration value sets the maximum number of tasks to execute concurrently on one node at any given time and defaults to 8. This parameter is effective on the worker nodes and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for the change to take effect.

This configuration entry ensures that you don't have many tasks hitting disk at the same time and helps in avoiding disk I/O contention. If your queries are served from memory or SSDs, you can increase max_running_tasks_per_node without much concern.

partition_buffer_size (integer)
************************************************

Sets the buffer size to use for partition operations and defaults to 8MB. CitusDB allows for table data to be re-partitioned into multiple files when two large tables are being joined. After this partition buffer fills up, the repartitioned data is flushed into files on disk. This configuration entry can be set at run-time and is effective on the worker nodes.
