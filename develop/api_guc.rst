.. _configuration:

Configuration Reference
=======================

There are various configuration parameters that affect the behaviour of Citus. These include both standard PostgreSQL parameters and Citus specific parameters. To learn more about PostgreSQL configuration parameters, you can visit the `run time configuration <http://www.postgresql.org/docs/current/static/runtime-config.html>`_ section of PostgreSQL documentation.

The rest of this reference aims at discussing Citus specific configuration parameters. These parameters can be set similar to PostgreSQL parameters by modifying postgresql.conf or `by using the SET command <http://www.postgresql.org/docs/current/static/config-setting.html>`_.

As an example you can update a setting with:

.. code-block:: postgresql

    ALTER DATABASE citus SET citus.multi_task_query_log_level = 'log';


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

citus.enable_version_checks (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

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

Sets the time to wait before checking for distributed deadlocks. In particular the time to wait will be this value multiplied by PostgreSQL's `deadlock_timeout <https://www.postgresql.org/docs/current/static/runtime-config-locks.html>`_ setting. The default value is ``2``. A value of ``-1`` disables distributed deadlock detection.

.. _node_connection_timeout:

citus.node_connection_timeout (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The ``citus.node_connection_timeout`` GUC sets the maximum duration (in milliseconds) to wait for connection establishment. Citus raises an error if the timeout elapses before at least one worker connection is established. This GUC affects connections from the coordinator to workers, and workers to each other.

* Default: thirty seconds
* Minimum: ten milliseconds
* Maximum: one hour

.. code-block:: postgresql

  -- set to 60 seconds
  ALTER DATABASE foo
  SET citus.node_connection_timeout = 60000;

.. _node_conninfo:

citus.node_conninfo (text)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The ``citus.node_conninfo`` GUC sets non-sensitive `libpq connection parameters <https://www.postgresql.org/docs/current/static/libpq-connect.html#LIBPQ-PARAMKEYWORDS>`_ used for all inter-node connections.

.. code-block:: postgresql

  -- key=value pairs separated by spaces.
  -- For example, ssl options:

  ALTER DATABASE foo
  SET citus.node_conninfo =
    'sslrootcert=/path/to/citus.crt sslmode=verify-full';

Citus honors only a specific subset of the allowed options, namely:

* application_name
* connect_timeout
* gsslib†
* keepalives
* keepalives_count
* keepalives_idle
* keepalives_interval
* krbsrvname†
* sslcompression
* sslcrl
* sslmode  (defaults to "require" as of Citus 8.1)
* sslrootcert
* tcp_user_timeout

*(† = subject to the runtime presence of optional PostgreSQL features)*

The ``node_conninfo`` setting takes effect only on newly opened connections. To force all connections to use the new settings, make sure to reload the postgres configuration:

.. code-block:: postgresql

   SELECT pg_reload_conf();

.. warning::

   Citus versions prior to 9.2.4 require a full database restart to force all connections to use the new setting.

.. _local_hostname:

citus.local_hostname (text)
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus nodes need occasionally to connect to themselves for systems operations.
By default, they use the address ``localhost`` to refer to themselves, but this
can cause problems. For instance, when a host requires ``sslmode=verify-full``
for incoming connections, adding ``localhost`` as an alternative hostname on
the SSL certificate isn't always desirable -- or even feasible.

``citus.local_hostname`` selects the hostname a node uses to connect to itself.
The default value is ``localhost``.

.. code-block:: postgresql

   ALTER SYSTEM SET citus.local_hostname TO 'mynode.example.com';

.. _hide_shards_from_app_name_prefixes:

citus.hide_shards_from_app_name_prefixes (text)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

By default, Citus hides shards from the list of tables PostgreSQL gives to SQL
clients. It does this because there are multiple shards per distributed table,
and the shards can be distracting to the SQL client.

The citus.hide_shards_from_app_name_prefixes GUC allows shards to be displayed
for selected clients that want to see them. Its default value is ``'*'``.

.. code-block:: psql

   -- hide shards from pgAdmin only (show in other clients, like psql)

   SET citus.hide_shards_from_app_name_prefixes TO 'pgAdmin*';

   -- also accepts a comma separated list

   SET citus.hide_shards_from_app_name_prefixes TO 'psql,pg_dump';

Query Statistics
---------------------------

citus.stat_statements_purge_interval (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

   This GUC is a part of our :ref:`cloud_topic` only.

Sets the frequency at which the maintenance daemon removes records from :ref:`citus_stat_statements <citus_stat_statements>` that are unmatched in ``pg_stat_statements``. This configuration value sets the time interval between purges in seconds, with a default value of 10. A value of 0 disables the purges.

.. code-block:: psql

   SET citus.stat_statements_purge_interval TO 5;

This parameter is effective on the coordinator and can be changed at runtime.

citus.stat_statements_max (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

   This GUC is a part of our :ref:`cloud_topic` only.

The maximum number of rows to store in :ref:`citus_stat_statements <citus_stat_statements>`. Defaults to 50000, and may be changed to any value in the range 1000 - 10000000. Note that each row requires 140 bytes of storage, so setting stat_statements_max to its maximum value of 10M would consume 1.4GB of memory.

Changing this GUC will not take effect until PostgreSQL is restarted.

citus.stat_statements_track (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

   This GUC is a part of our :ref:`cloud_topic` only.

Recording statistics for :ref:`citus_stat_statements <citus_stat_statements>`
requires extra CPU resources. When the database is experiencing load, the
administrator may wish to disable statement tracking. The
``citus.stat_statements_track`` GUC can turn tracking on and off. 

* **all**: (default) Track all statements.
* **none**: Disable tracking.

Data Loading
---------------------------

citus.multi_shard_commit_protocol (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the commit protocol to use when performing COPY on a hash distributed table. On each individual shard placement, the COPY is performed in a transaction block to ensure that no data is ingested if an error occurs during the COPY. However, there is a particular failure case in which the COPY succeeds on all placements, but a (hardware) failure occurs before all transactions commit. This parameter can be used to prevent data loss in that case by choosing between the following commit protocols: 

* **2pc:** (default) The transactions in which COPY is performed on the shard placements are first prepared using PostgreSQL's `two-phase commit <http://www.postgresql.org/docs/current/static/sql-prepare-transaction.html>`_ and then committed. Failed commits can be manually recovered or aborted using COMMIT PREPARED or ROLLBACK PREPARED, respectively. When using 2pc, `max_prepared_transactions <http://www.postgresql.org/docs/current/static/runtime-config-resource.html>`_ should be increased on all the workers, typically to the same value as max_connections.

* **1pc:** The transactions in which COPY is performed on the shard placements are committed in a single round. Data may be lost if a commit fails after COPY succeeds on all placements (rare).

citus.shard_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the shard count for hash-partitioned tables and defaults to 32. This value is used by
the :ref:`create_distributed_table <create_distributed_table>` UDF when creating
hash-partitioned tables. This parameter can be set at run-time and is effective on the coordinator. 

citus.shard_max_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the maximum size to which a shard will grow before it gets split and defaults to 1GB. When the source file's size (which is used for staging) for one shard exceeds this configuration value, the database ensures that a new shard gets created. This parameter can be set at run-time and is effective on the coordinator.

.. _replicate_reference_tables_on_activate:

citus.replicate_reference_tables_on_activate (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Reference table shards must be placed on all nodes which have distributed
tables. By default, reference table shards are copied to a node at node
activation time, that is, when such functions as :ref:`citus_add_node` or
:ref:`citus_activate_node` are called. However, node activation might be an
inconvenient time to copy the placements, because it can take a long time when
there are large reference tables.

You can defer reference table replication by setting the
``citus.replicate_reference_tables_on_activate`` GUC to 'off'. Reference table
replication will then happen when we create new shards on the node. For instance,
when calling :ref:`create_distributed_table`, :ref:`create_reference_table`,
or when the shard rebalancer moves shards to the new node.

The default value for this GUC is 'on'.

Planner Configuration
------------------------------------------------

.. _local_table_join_policy:

citus.local_table_join_policy (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

This GUC determines how Citus moves data when doing a join between local and
distributed tables. Customizing the join policy can help reduce the amount of
data sent between worker nodes.

Citus will send either the local or distributed tables to nodes as necessary to
support the join. Copying table data is referred to as a "conversion." If a
local table is converted, then it will be sent to any workers that need its
data to perform the join.  If a distributed table is converted, then it will be
collected in the coordinator to support the join.  The citus planner will send
only the necessary rows doing a conversion.

There are four modes available to express conversion preference:

* **auto:** (Default) Citus will convert either all local or all distributed
  tables to support local and distributed table joins. Citus decides which to
  convert using a heuristic. It will convert distributed tables if they are
  joined using a constant filter on a unique index (such as a primary key).
  This ensures less data gets moved between workers.

* **never:** Citus will not allow joins between local and distributed tables.

* **prefer-local:** Citus will prefer converting local tables to support local
  and distributed table joins.

* **prefer-distributed:** Citus will prefer converting distributed tables to
  support local and distributed table joins. If the distributed tables are
  huge, using this option might result in moving lots of data between workers.

For example, assume ``citus_table`` is a distributed table distributed by the
column ``x``, and that ``postgres_table`` is a local table:

.. code-block:: postgresql

   CREATE TABLE citus_table(x int primary key, y int);
   SELECT create_distributed_table('citus_table', 'x');

   CREATE TABLE postgres_table(x int, y int);

   -- even though the join is on primary key, there isn't a constant filter
   -- hence postgres_table will be sent to worker nodes to support the join
   SELECT * FROM citus_table JOIN postgres_table USING (x);

   -- there is a constant filter on a primary key, hence the filtered row
   -- from the distributed table will be pulled to coordinator to support the join
   SELECT * FROM citus_table JOIN postgres_table USING (x) WHERE citus_table.x = 10;

   SET citus.local_table_join_policy to 'prefer-distributed';
   -- since we prefer distributed tables, citus_table will be pulled to coordinator
   -- to support the join. Note that citus_table can be huge.
   SELECT * FROM citus_table JOIN postgres_table USING (x);

   SET citus.local_table_join_policy to 'prefer-local';
   -- even though there is a constant filter on primary key for citus_table
   -- postgres_table will be sent to necessary workers because we are using 'prefer-local'.
   SELECT * FROM citus_table JOIN postgres_table USING (x) WHERE citus_table.x = 10;

citus.limit_clause_row_fetch_count (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the number of rows to fetch per task for limit clause optimization. In some cases, select queries with limit clauses may need to fetch all rows from each task to generate results. In those cases, and where an approximation would produce meaningful results, this configuration value sets the number of rows to fetch from each shard. Limit approximations are disabled by default and this parameter is set to -1. This value can be set at run-time and is effective on the coordinator.

citus.count_distinct_error_rate (floating point)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus can calculate count(distinct) approximates using the postgresql-hll extension. This configuration entry sets the desired error rate when calculating count(distinct). 0.0, which is the default, disables approximations for count(distinct); and 1.0 provides no guarantees about the accuracy of results. We recommend setting this parameter to 0.005 for best results. This value can be set at run-time and is effective on the coordinator.

citus.task_assignment_policy (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

   This GUC is applicable for queries against :ref:`reference_tables`.

Sets the policy to use when assigning tasks to workers. The coordinator assigns tasks to workers based on shard locations. This configuration value specifies the policy to use when making these assignments. Currently, there are three possible task assignment policies which can be used.

* **greedy:** The greedy policy is the default and aims to evenly distribute tasks across workers.

* **round-robin:** The round-robin policy assigns tasks to workers in a round-robin fashion alternating between different replicas. This enables much better cluster utilization when the shard count for a table is low compared to the number of workers.

* **first-replica:** The first-replica policy assigns tasks on the basis of the insertion order of placements (replicas) for the shards. In other words, the fragment query for a shard is simply assigned to the worker which has the first replica of that shard. This method allows you to have strong guarantees about which shards will be used on which nodes (i.e. stronger memory residency guarantees).

This parameter can be set at run-time and is effective on the coordinator.

Intermediate Data Transfer
-------------------------------------------------------------------

.. _binary_worker_copy_format:

citus.binary_worker_copy_format (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Use the binary copy format to transfer intermediate data between workers. During large table joins, Citus may have to dynamically repartition and shuffle data between different workers. For Postgres 13 and lower, the default for this setting is ``false``, which means text encoding is used to transfer this data. For Postgres 14 and higher, the default is ``true``. Setting this parameter is ``true`` instructs the database to use PostgreSQL’s binary serialization format to transfer data. The parameter is effective on the workers and needs to be changed in the postgresql.conf file. After editing the config file, users can send a SIGHUP signal or restart the server for this change to take effect.

citus.max_intermediate_result_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The maximum size in KB of intermediate results for CTEs that are unable to be pushed down to worker nodes for execution, and for complex subqueries. The default is 1GB, and a value of -1 means no limit. Queries exceeding the limit will be canceled and produce an error message.

DDL
-------------------------------------------------------------------

.. _enable_ddl_prop:

citus.enable_ddl_propagation (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Specifies whether to automatically propagate DDL changes from the coordinator to all workers. The default value is true. Because some schema changes require an access exclusive lock on tables and because the automatic propagation applies to all workers sequentially it can make a Citus cluster temporarily less responsive. You may choose to disable this setting and propagate changes manually.

.. note::

  For a list of DDL propagation support, see :ref:`ddl_prop_support`.

.. _enable_local_ref_fkeys:

citus.enable_local_reference_table_foreign_keys (boolean)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

This setting, enabled by default, allows foreign keys to be created between reference and local
tables. For the feature to work, the coordinator node must be registered with itself, using
:ref:`citus_add_node`.

Note that foreign keys between reference tables and local tables come at a slight cost. When
you create the foreign key, Citus must add the plain table to Citus' metadata, and
track it in :ref:`partition_table`. Local tables that are added to metadata inherit the same
limitations as reference tables (see :ref:`ddl` and :ref:`citus_sql_reference`)..

If you drop the foreign keys, Citus will automatically remove such local tables from metadata,
which eliminates such limitations on those tables.

.. _executor_configuration:

Executor Configuration
------------------------------------------------------------

General
$$$$$$$

citus.all_modifications_commutative
************************************

Citus enforces commutativity rules and acquires appropriate locks for modify operations in order to guarantee correctness of behavior. For example, it assumes that an INSERT statement commutes with another INSERT statement, but not with an UPDATE or DELETE statement. Similarly, it assumes that an UPDATE or DELETE statement does not commute with another UPDATE or DELETE statement. This means that UPDATEs and DELETEs require Citus to acquire stronger locks.

If you have UPDATE statements that are commutative with your INSERTs or other UPDATEs, then you can relax these commutativity assumptions by setting this parameter to true. When this parameter is set to true, all commands are considered commutative and claim a shared lock, which can improve overall throughput. This parameter can be set at runtime and is effective on the coordinator.

.. _multi_task_logging:

citus.multi_task_query_log_level (enum)
*****************************************

Sets a log-level for any query which generates more than one task (i.e. which
hits more than one shard). This is useful during a multi-tenant application
migration, as you can choose to error or warn for such queries, to find them and
add a tenant_id filter to them. This parameter can be set at runtime and is
effective on the coordinator. The default value for this parameter is 'off'.

The supported values for this enum are:

* **off:** Turn off logging any queries which generate multiple tasks (i.e. span multiple shards)

* **debug:** Logs statement at DEBUG severity level.

* **log:** Logs statement at LOG severity level. The log line will include the SQL query that was run.

* **notice:** Logs statement at NOTICE severity level.

* **warning:** Logs statement at WARNING severity level.

* **error:** Logs statement at ERROR severity level.

Note that it may be useful to use :code:`error` during development testing, and a lower log-level like :code:`log` during actual production deployment. Choosing ``log`` will cause multi-task queries to appear in the database logs with the query itself shown after "STATEMENT."

.. code-block:: text

  LOG:  multi-task query about to be executed
  HINT:  Queries are split to multiple tasks if they have to be split into several queries on the workers.
  STATEMENT:  select * from foo;

citus.propagate_set_commands (enum)
***********************************

Determines which SET commands are propagated from the coordinator to workers.
The default value for this parameter is 'none'.

The supported values are:

* **none:** no SET commands are propagated.

* **local:** only SET LOCAL commands are propagated.

citus.enable_repartition_joins (boolean)
****************************************

Ordinarily, attempting to perform :ref:`repartition_joins` with the adaptive executor will fail with an error message. However, setting ``citus.enable_repartition_joins`` to true allows Citus to perform the join. The default value is false.

.. _enable_repartitioned_insert_select:

citus.enable_repartitioned_insert_select (boolean)
**************************************************

By default, an INSERT INTO … SELECT statement that cannot be pushed down will attempt to repartition rows from the SELECT statement and transfer them between workers for insertion. However, if the target table has too many shards then repartitioning will probably not perform well. The overhead of processing the shard intervals when determining how to partition the results is too great. Repartitioning can be disabled manually by setting ``citus.enable_repartitioned_insert_select`` to false.

citus.enable_binary_protocol (boolean)
**************************************

Setting this parameter to true instructs the coordinator node to use
PostgreSQL's binary serialization format (when applicable) to transfer data
with workers. Some column types do not support binary serialization.

Enabling this parameter is mostly useful when the workers must return large
amounts of data.  Examples are when a lot of rows are requested, the rows have
many columns, or they use big types such as ``hll`` from the postgresql-hll
extension.

The default value is ``true`` for Postgres versions 14 and higher. For Postgres
versions 13 and lower the default is ``false``, which means all results are
encoded and transferred in text format.

.. _max_shared_pool_size:

citus.max_shared_pool_size (integer)
************************************

Specifies the maximum number of connections that the coordinator node, across
all simultaneous sessions, is allowed to make per worker node. PostgreSQL must
allocate fixed resources for every connection and this GUC helps ease
connection pressure on workers.

Without connection throttling, every multi-shard query creates connections on
each worker proportional to the number of shards it accesses (in particular, up
to #shards/#workers). Running dozens of multi-shard queries at once can easily
hit worker nodes' ``max_connections`` limit, causing queries to fail.

By default, the value is automatically set equal to the coordinator's own
``max_connections``, which isn't guaranteed to match that of the workers (see
the note below). The value -1 disables throttling.

.. note::

  There are certain operations that do not obey citus.max_shared_pool_size,
  most importantly repartition joins. That's why it can be prudent to increase
  the max_connections on the workers a bit higher than max_connections
  on the coordinator. This gives extra space for connections required for
  repartition queries on the workers.

.. _max_adaptive_executor_pool_size:

citus.max_adaptive_executor_pool_size (integer)
***********************************************

Whereas :ref:`max_shared_pool_size` limits worker connections across all
sessions, ``max_adaptive_executor_pool_size`` limits worker connections from
just the *current* session. This GUC is useful for:

* Preventing a single backend from getting all the worker resources
* Providing priority management: designate low priority sessions with low
  max_adaptive_executor_pool_size, and high priority sessions with higher
  values

The default value is 16.

.. _executor_slow_start_interval:

citus.executor_slow_start_interval (integer)
********************************************

Time to wait in milliseconds between opening connections to the same worker
node.

When the individual tasks of a multi-shard query take very little time, they
can often be finished over a single (often already cached) connection. To avoid
redundantly opening additional connections, the executor waits between
connection attempts for the configured number of milliseconds. At the end of
the interval, it increases the number of connections it is allowed to open next
time.

For long queries (those taking >500ms), slow start might add latency, but for
short queries it's faster. The default value is 10ms.

.. _max_cached_conns_per_worker:

citus.max_cached_conns_per_worker (integer)
*******************************************

Each backend opens connections to the workers to query the shards. At the end
of the transaction, the configured number of connections is kept open to speed
up subsequent commands.  Increasing this value will reduce the latency of
multi-shard queries, but will also increase overhead on the workers.

The default value is 1. A larger value such as 2 might be helpful for clusters
that use a small number of concurrent sessions, but it's not wise to go much
further (e.g. 16 would be too high).

.. _force_max_query_parallelization:

citus.force_max_query_parallelization (boolean)
***********************************************

Simulates the deprecated and now nonexistent real-time executor. This is used
to open as many connections as possible to maximize query parallelization.

When this GUC is enabled, Citus will force the adaptive executor to use as many
connections as possible while executing a parallel distributed query. If not
enabled, the executor might choose to use fewer connections to optimize overall
query execution throughput. Internally, setting this true will end up using one
connection per task.

One place where this is useful is in a transaction whose first query is
lightweight and requires few connections, while a subsequent query would
benefit from more connections. Citus decides how many connections to use in a
transaction based on the first statement, which can throttle other queries
unless we use the GUC to provide a hint.

.. code-block:: postgresql

    BEGIN;
    -- add this hint
    SET citus.force_max_query_parallelization TO ON;

    -- a lightweight query that doesn't require many connections
    SELECT count(*) FROM table WHERE filter = x;

    -- a query that benefits from more connections, and can obtain
    -- them since we forced max parallelization above
    SELECT ... very .. complex .. SQL;
    COMMIT;

The default value is false.

Explain output
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

citus.explain_all_tasks (boolean)
************************************************

By default, Citus shows the output of a single, arbitrary task when running `EXPLAIN <http://www.postgresql.org/docs/current/static/sql-explain.html>`_ on a distributed query. In most cases, the explain output will be similar across tasks. Occasionally, some of the tasks will be planned differently or have much higher execution times. In those cases, it can be useful to enable this parameter, after which the EXPLAIN output will include all tasks. This may cause the EXPLAIN to take longer.

.. _explain_analyze_sort_method:

citus.explain_analyze_sort_method (enum)
************************************************

Determines the sort method of the tasks in the output of EXPLAIN ANALYZE.
The default value of citus.explain_analyze_sort_method is ``execution-time``.

The supported values are:

* **execution-time:** sort by execution time.

* **taskId:** sort by task id.
