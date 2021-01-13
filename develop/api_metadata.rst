.. _metadata_tables:

Citus Tables and Views
======================

Coordinator Metadata
--------------------

Citus divides each distributed table into multiple logical shards based on the distribution column. The coordinator then maintains metadata tables to track statistics and information about the health and location of these shards. In this section, we describe each of these metadata tables and their schema. You can view and query these tables using SQL after logging into the coordinator node.

.. _partition_table:

Partition table
~~~~~~~~~~~~~~~~~

The pg_dist_partition table stores metadata about which tables in the database are distributed. For each distributed table, it also stores information about the distribution method and detailed information about the distribution column.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| logicalrelid   |         regclass     | | Distributed table to which this row corresponds. This value references  |
|                |                      | | the relfilenode column in the pg_class system catalog table.            |
+----------------+----------------------+---------------------------------------------------------------------------+
|  partmethod    |         char         | | The method used for partitioning / distribution. The values of this     |
|                |                      | | column corresponding to different distribution methods are :-           |
|                |                      | | append: 'a'                                                             |
|                |                      | | hash: 'h'                                                               |
|                |                      | | reference table: 'n'                                                    |
+----------------+----------------------+---------------------------------------------------------------------------+
|   partkey      |         text         | | Detailed information about the distribution column including column     |
|                |                      | | number, type and other relevant information.                            |
+----------------+----------------------+---------------------------------------------------------------------------+
|   colocationid |         integer      | | Co-location group to which this table belongs. Tables in the same group |
|                |                      | | allow co-located joins and distributed rollups among other              |
|                |                      | | optimizations. This value references the colocationid column in the     |
|                |                      | | pg_dist_colocation table.                                               |
+----------------+----------------------+---------------------------------------------------------------------------+
|   repmodel     |         char         | | The method used for data replication. The values of this column         |
|                |                      | | corresponding to different replication methods are :-                   |
|                |                      | | * citus statement-based replication: 'c'                                |
|                |                      | | * postgresql streaming replication:  's'                                |
|                |                      | | * two-phase commit (for reference tables): 't'                          |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_partition;
     logicalrelid  | partmethod |                                                        partkey                                                         | colocationid | repmodel 
    ---------------+------------+------------------------------------------------------------------------------------------------------------------------+--------------+----------
     github_events | h          | {VAR :varno 1 :varattno 4 :vartype 20 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnoold 1 :varoattno 4 :location -1} |            2 | c
     (1 row)

.. _pg_dist_shard:

Shard table
~~~~~~~~~~~~~~~~~

The pg_dist_shard table stores metadata about individual shards of a table. This includes information about which distributed table the shard belongs to and statistics about the distribution column for that shard. For append distributed tables, these statistics correspond to min / max values of the distribution column. In case of hash distributed tables, they are hash token ranges assigned to that shard. These statistics are used for pruning away unrelated shards during SELECT queries.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| logicalrelid   |         regclass     | | Distributed table to which this shard belongs. This value references the|
|                |                      | | relfilenode column in the pg_class system catalog table.                |
+----------------+----------------------+---------------------------------------------------------------------------+
|    shardid     |         bigint       | | Globally unique identifier assigned to this shard.                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardstorage   |            char      | | Type of storage used for this shard. Different storage types are        |
|                |                      | | discussed in the table below.                                           |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardminvalue  |            text      | | For append distributed tables, minimum value of the distribution column |
|                |                      | | in this shard (inclusive).                                              |
|                |                      | | For hash distributed tables, minimum hash token value assigned to that  |
|                |                      | | shard (inclusive).                                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardmaxvalue  |            text      | | For append distributed tables, maximum value of the distribution column |
|                |                      | | in this shard (inclusive).                                              |
|                |                      | | For hash distributed tables, maximum hash token value assigned to that  |
|                |                      | | shard (inclusive).                                                      |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_shard;
     logicalrelid  | shardid | shardstorage | shardminvalue | shardmaxvalue 
    ---------------+---------+--------------+---------------+---------------
     github_events |  102026 | t            | 268435456     | 402653183
     github_events |  102027 | t            | 402653184     | 536870911
     github_events |  102028 | t            | 536870912     | 671088639
     github_events |  102029 | t            | 671088640     | 805306367
     (4 rows)


Shard Storage Types
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The shardstorage column in pg_dist_shard indicates the type of storage used for the shard. A brief overview of different shard storage types and their representation is below.


+----------------+----------------------+-----------------------------------------------------------------------------+
|  Storage Type  |  Shardstorage value  |       Description                                                           |
+================+======================+=============================================================================+
|   TABLE        |           't'        | | Indicates that shard stores data belonging to a regular                   |
|                |                      | | distributed table.                                                        |
+----------------+----------------------+-----------------------------------------------------------------------------+   
|  COLUMNAR      |            'c'       | | Indicates that shard stores columnar data. (Used by                       |
|                |                      | | distributed cstore_fdw tables)                                            |
+----------------+----------------------+-----------------------------------------------------------------------------+
|   FOREIGN      |            'f'       | | Indicates that shard stores foreign data. (Used by                        |
|                |                      | | distributed file_fdw tables)                                              |
+----------------+----------------------+-----------------------------------------------------------------------------+


.. _placements:

Shard placement table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pg_dist_placement table tracks the location of shard replicas on worker nodes. Each replica of a shard assigned to a specific node is called a shard placement. This table stores information about the health and location of each shard placement.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| placementid    |       bigint         | | Unique auto-generated identifier for each individual placement.         |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardid        |       bigint         | | Shard identifier associated with this placement. This value references  |
|                |                      | | the shardid column in the pg_dist_shard catalog table.                  |
+----------------+----------------------+---------------------------------------------------------------------------+ 
| shardstate     |         int          | | Describes the state of this placement. Different shard states are       |
|                |                      | | discussed in the section below.                                         |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardlength    |       bigint         | | For append distributed tables, the size of the shard placement on the   |
|                |                      | | worker node in bytes.                                                   |
|                |                      | | For hash distributed tables, zero.                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| groupid        |         int          | | Identifier used to denote a group of one primary server and zero or more|
|                |                      | | secondary servers, when the streaming replication model is used.        |
+----------------+----------------------+---------------------------------------------------------------------------+

::

  SELECT * from pg_dist_placement;
    placementid | shardid | shardstate | shardlength | groupid
   -------------+---------+------------+-------------+---------
              1 |  102008 |          1 |           0 |       1
              2 |  102008 |          1 |           0 |       2
              3 |  102009 |          1 |           0 |       2
              4 |  102009 |          1 |           0 |       3
              5 |  102010 |          1 |           0 |       3
              6 |  102010 |          1 |           0 |       4
              7 |  102011 |          1 |           0 |       4

.. note::

  As of Citus 7.0 the analogous table :code:`pg_dist_shard_placement` has been deprecated. It included the node name and port for each placement:

  ::

    SELECT * from pg_dist_shard_placement;
      shardid | shardstate | shardlength | nodename  | nodeport | placementid 
     ---------+------------+-------------+-----------+----------+-------------
       102008 |          1 |           0 | localhost |    12345 |           1
       102008 |          1 |           0 | localhost |    12346 |           2
       102009 |          1 |           0 | localhost |    12346 |           3
       102009 |          1 |           0 | localhost |    12347 |           4
       102010 |          1 |           0 | localhost |    12347 |           5
       102010 |          1 |           0 | localhost |    12345 |           6
       102011 |          1 |           0 | localhost |    12345 |           7

  That information is now available by joining pg_dist_placement with :ref:`pg_dist_node <pg_dist_node>` on the groupid. For compatibility Citus still provides pg_dist_shard_placement as a view. However we recommend using the new, more normalized, tables when possible.


Shard Placement States
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus manages shard health on a per-placement basis and automatically marks a placement as unavailable if leaving the placement in service would put the cluster in an inconsistent state. The shardstate column in the pg_dist_placement table is used to store the state of shard placements. A brief overview of different shard placement states and their representation is below.


+----------------+----------------------+---------------------------------------------------------------------------+
|  State name    |  Shardstate value    |       Description                                                         |
+================+======================+===========================================================================+
|   FINALIZED    |           1          | | This is the state new shards are created in. Shard placements           |
|                |                      | | in this state are considered up-to-date and are used in query   	    |
|                |                      | | planning and execution.                                                 |
+----------------+----------------------+---------------------------------------------------------------------------+   
|  INACTIVE      |            3         | | Shard placements in this state are considered inactive due to           |
|                |                      | | being out-of-sync with other replicas of the same shard. This           |
|                |                      | | can occur when an append, modification (INSERT, UPDATE or               |
|                |                      | | DELETE ) or a DDL operation fails for this placement. The query         |
|                |                      | | planner will ignore placements in this state during planning and        |
|                |                      | | execution. Users can synchronize the data in these shards with          |
|                |                      | | a finalized replica as a background activity.                           |
+----------------+----------------------+---------------------------------------------------------------------------+
|   TO_DELETE    |            4         | | If Citus attempts to drop a shard placement in response to a            |
|                |                      | | master_apply_delete_command call and fails, the placement is            |
|                |                      | | moved to this state. Users can then delete these shards as a            |
|                |                      | | subsequent background activity.                                         |
+----------------+----------------------+---------------------------------------------------------------------------+


.. _pg_dist_node:

Worker node table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pg_dist_node table contains information about the worker nodes in the cluster. 

+------------------+----------------------+---------------------------------------------------------------------------+
|      Name        |         Type         |       Description                                                         |
+==================+======================+===========================================================================+
| nodeid           |         int          | | Auto-generated identifier for an individual node.                       |
+------------------+----------------------+---------------------------------------------------------------------------+
| groupid          |         int          | | Identifier used to denote a group of one primary server and zero or more|
|                  |                      | | secondary servers, when the streaming replication model is used. By     |
|                  |                      | | default it is the same as the nodeid.                                   |
+------------------+----------------------+---------------------------------------------------------------------------+
| nodename         |         text         | | Host Name or IP Address of the PostgreSQL worker node.                  |
+------------------+----------------------+---------------------------------------------------------------------------+
| nodeport         |         int          | | Port number on which the PostgreSQL worker node is listening.           |
+------------------+----------------------+---------------------------------------------------------------------------+
| noderack         |        text          | | (Optional) Rack placement information for the worker node.              |
+------------------+----------------------+---------------------------------------------------------------------------+
| hasmetadata      |        boolean       | | Reserved for internal use.                                              |
+------------------+----------------------+---------------------------------------------------------------------------+
| isactive         |        boolean       | | Whether the node is active accepting shard placements.                  |
+------------------+----------------------+---------------------------------------------------------------------------+
| noderole         |        text          | | Whether the node is a primary or secondary                              |
+------------------+----------------------+---------------------------------------------------------------------------+
| nodecluster      |        text          | | The name of the cluster containing this node                            |
+------------------+----------------------+---------------------------------------------------------------------------+
| metadatasynced   |        boolean       | | Reserved for internal use.                                              |
+------------------+----------------------+---------------------------------------------------------------------------+
| shouldhaveshards |        boolean       | | If false, shards will be moved off node (drained) when rebalancing,     |
|                  |                      | | nor will shards from new distributed tables be placed on the node,      |
|                  |                      | | unless they are colocated with shards already there                     |
+------------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_node;
     nodeid | groupid | nodename  | nodeport | noderack | hasmetadata | isactive | noderole | nodecluster | metadatasynced | shouldhaveshards
    --------+---------+-----------+----------+----------+-------------+----------+----------+-------------+----------------+------------------
          1 |       1 | localhost |    12345 | default  | f           | t        | primary  | default     | f              | t
          2 |       2 | localhost |    12346 | default  | f           | t        | primary  | default     | f              | t
          3 |       3 | localhost |    12347 | default  | f           | t        | primary  | default     | f              | t
    (3 rows)

.. _pg_dist_object:

Distributed object table
~~~~~~~~~~~~~~~~~~~~~~~~

The citus.pg_dist_object table contains a list of objects such as types and
functions that have been created on the coordinator node and propagated to
worker nodes. When an administrator adds new worker nodes to the cluster, Citus
automatically creates copies of the distributed objects on the new nodes (in
the correct order to satisfy object dependencies).

+-----------------------------+---------+------------------------------------------------------+
| Name                        | Type    | Description                                          |
+=============================+=========+======================================================+
| classid                     | oid     | Class of the distributed object                      |
+-----------------------------+---------+------------------------------------------------------+
| objid                       | oid     | Object id of the distributed object                  |
+-----------------------------+---------+------------------------------------------------------+
| objsubid                    | integer | Object sub id of the distributed object, e.g. attnum |
+-----------------------------+---------+------------------------------------------------------+
| type                        | text    | Part of the stable address used during pg upgrades   |
+-----------------------------+---------+------------------------------------------------------+
| object_names                | text[]  | Part of the stable address used during pg upgrades   |
+-----------------------------+---------+------------------------------------------------------+
| object_args                 | text[]  | Part of the stable address used during pg upgrades   |
+-----------------------------+---------+------------------------------------------------------+
| distribution_argument_index | integer | Only valid for distributed functions/procedures      |
+-----------------------------+---------+------------------------------------------------------+
| colocationid                | integer | Only valid for distributed functions/procedures      |
+-----------------------------+---------+------------------------------------------------------+

"Stable addresses" uniquely identify objects independently of a specific
server.  Citus tracks objects during a PostgreSQL upgrade using stable
addresses created with the `pg_identify_object_as_address()
<https://www.postgresql.org/docs/current/functions-info.html#FUNCTIONS-INFO-OBJECT-TABLE>`_
function.

Here's an example of how ``create_distributed_function()`` adds entries to the
``citus.pg_dist_object`` table:

.. code-block:: psql

    CREATE TYPE stoplight AS enum ('green', 'yellow', 'red');

    CREATE OR REPLACE FUNCTION intersection()
    RETURNS stoplight AS $$
    DECLARE
            color stoplight;
    BEGIN
            SELECT *
              FROM unnest(enum_range(NULL::stoplight)) INTO color
             ORDER BY random() LIMIT 1;
            RETURN color;
    END;
    $$ LANGUAGE plpgsql VOLATILE;

    SELECT create_distributed_function('intersection()');

    -- will have two rows, one for the TYPE and one for the FUNCTION
    TABLE citus.pg_dist_object;

.. code-block:: text

    -[ RECORD 1 ]---------------+------
    classid                     | 1247
    objid                       | 16780
    objsubid                    | 0
    type                        |
    object_names                |
    object_args                 |
    distribution_argument_index |
    colocationid                |
    -[ RECORD 2 ]---------------+------
    classid                     | 1255
    objid                       | 16788
    objsubid                    | 0
    type                        |
    object_names                |
    object_args                 |
    distribution_argument_index |
    colocationid                |

.. _colocation_group_table:

Co-location group table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pg_dist_colocation table contains information about which tables' shards should be placed together, or :ref:`co-located <colocation>`. When two tables are in the same co-location group, Citus ensures shards with the same partition values will be placed on the same worker nodes. This enables join optimizations, certain distributed rollups, and foreign key support. Shard co-location is inferred when the shard counts, replication factors, and partition column types all match between two tables; however, a custom co-location group may be specified when creating a distributed table, if so desired.

+-----------------------------+----------------------+---------------------------------------------------------------------------+
|      Name                   |         Type         |       Description                                                         |
+=============================+======================+===========================================================================+
| colocationid                |         int          | | Unique identifier for the co-location group this row corresponds to.    |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| shardcount                  |         int          | | Shard count for all tables in this co-location group                    |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| replicationfactor           |         int          | | Replication factor for all tables in this co-location group.            |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| distributioncolumntype      |         oid          | | The type of the distribution column for all tables in this              |
|                             |                      | | co-location group.                                                      |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| distributioncolumncollation |         oid          | | The collation of the distribution column for all tables in              |
|                             |                      | | this co-location group.                                                 |
+-----------------------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_colocation;
      colocationid | shardcount | replicationfactor | distributioncolumntype | distributioncolumncollation
     --------------+------------+-------------------+------------------------+-----------------------------
                 2 |         32 |                 2 |                     20 |                           0
      (1 row)

.. _pg_dist_rebalance_strategy:

Rebalancer strategy table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::

  The pg_dist_rebalance_strategy table is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

This table defines strategies that :ref:`rebalance_table_shards` can use to determine where to move shards.

+--------------------------------+----------------------+---------------------------------------------------------------------------+
|      Name                      |         Type         |       Description                                                         |
+================================+======================+===========================================================================+
| name                           |         name         | | Unique name for the strategy                                            |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| default_strategy               |         boolean      | | Whether :ref:`rebalance_table_shards` should choose this strategy by    |
|                                |                      | | default. Use :ref:`citus_set_default_rebalance_strategy` to update      |
|                                |                      | | this column                                                             |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| shard_cost_function            |         regproc      | | Identifier for a cost function, which must take a shardid as bigint,    |
|                                |                      | | and return its notion of a cost, as type real                           |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| node_capacity_function         |         regproc      | | Identifier for a capacity function, which must take a nodeid as int,    |
|                                |                      | | and return its notion of node capacity as type real                     |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| shard_allowed_on_node_function |         regproc      | | Identifier for a function that given shardid bigint, and nodeidarg int, |
|                                |                      | | returns boolean for whether the shard is allowed to be stored on the    |
|                                |                      | | node                                                                    |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| default_threshold              |         float4       | | Threshold for deeming a node too full or too empty, which determines    |
|                                |                      | | when the rebalance_table_shards should try to move shards               |
+--------------------------------+----------------------+---------------------------------------------------------------------------+
| minimum_threshold              |         float4       | | A safeguard to prevent the threshold argument of                        |
|                                |                      | | rebalance_table_shards() from being set too low                         |
+--------------------------------+----------------------+---------------------------------------------------------------------------+

A Citus installation ships with these strategies in the table:

.. code-block:: postgres

    SELECT * FROM pg_dist_rebalance_strategy;

::

    -[ RECORD 1 ]-------------------+-----------------------------------
    Name                            | by_shard_count
    default_strategy                | true
    shard_cost_function             | citus_shard_cost_1
    node_capacity_function          | citus_node_capacity_1
    shard_allowed_on_node_function  | citus_shard_allowed_on_node_true
    default_threshold               | 0
    minimum_threshold               | 0
    -[ RECORD 2 ]-------------------+-----------------------------------
    Name                            | by_disk_size
    default_strategy                | false
    shard_cost_function             | citus_shard_cost_by_disk_size
    node_capacity_function          | citus_node_capacity_1
    shard_allowed_on_node_function  | citus_shard_allowed_on_node_true
    default_threshold               | 0.1
    minimum_threshold               | 0.01

The default strategy, ``by_shard_count``, assigns every shard the same cost. Its effect is to equalize the shard count across nodes. The other predefined strategy, ``by_disk_size``, assigns a cost to each shard matching its disk size in bytes plus that of the shards that are colocated with it. The disk size is calculated using ``pg_total_relation_size``, so it includes indices. This strategy attempts to achieve the same disk space on every node. Note the threshold of 0.1 -- it prevents unnecessary shard movement caused by insigificant differences in disk space.

.. _custom_rebalancer_strategies:

Creating custom rebalancer strategies
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Here are examples of functions that can be used within new shard rebalancer strategies, and registered in the :ref:`pg_dist_rebalance_strategy` with the :ref:`citus_add_rebalance_strategy` function.

* Setting a node capacity exception by hostname pattern:

  .. code-block:: postgres

      -- example of node_capacity_function

      CREATE FUNCTION v2_node_double_capacity(nodeidarg int)
          RETURNS real AS $$
          SELECT
              (CASE WHEN nodename LIKE '%.v2.worker.citusdata.com' THEN 2.0::float4 ELSE 1.0::float4 END)
          FROM pg_dist_node where nodeid = nodeidarg
          $$ LANGUAGE sql;
  
* Rebalancing by number of queries that go to a shard, as measured by the :ref:`citus_stat_statements`:
  
  .. code-block:: postgres
  
      -- example of shard_cost_function

      CREATE FUNCTION cost_of_shard_by_number_of_queries(shardid bigint)
          RETURNS real AS $$
          SELECT coalesce(sum(calls)::real, 0.001) as shard_total_queries
          FROM citus_stat_statements
          WHERE partition_key is not null
              AND get_shard_id_for_distribution_column('tab', partition_key) = shardid;
      $$ LANGUAGE sql;
  
* Isolating a specific shard (10000) on a node (address '10.0.0.1'):
  
  .. code-block:: postgres
  
      -- example of shard_allowed_on_node_function

      CREATE FUNCTION isolate_shard_10000_on_10_0_0_1(shardid bigint, nodeidarg int)
          RETURNS boolean AS $$
          SELECT
              (CASE WHEN nodename = '10.0.0.1' THEN shardid = 10000 ELSE shardid != 10000 END)
          FROM pg_dist_node where nodeid = nodeidarg
          $$ LANGUAGE sql;

      -- The next two definitions are recommended in combination with the above function.
      -- This way the average utilization of nodes is not impacted by the isolated shard.
      CREATE FUNCTION no_capacity_for_10_0_0_1(nodeidarg int)
          RETURNS real AS $$
          SELECT
              (CASE WHEN nodename = '10.0.0.1' THEN 0 ELSE 1 END)::real
          FROM pg_dist_node where nodeid = nodeidarg
          $$ LANGUAGE sql;
      CREATE FUNCTION no_cost_for_10000(shardid bigint)
          RETURNS real AS $$
          SELECT
              (CASE WHEN shardid = 10000 THEN 0 ELSE 1 END)::real
          $$ LANGUAGE sql;

.. _citus_stat_statements:

Query statistics table
~~~~~~~~~~~~~~~~~~~~~~

.. note::

  The citus_stat_statements view is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

Citus provides ``citus_stat_statements`` for stats about how queries are being executed, and for whom. It's analogous to (and can be joined with) the `pg_stat_statements <https://www.postgresql.org/docs/current/static/pgstatstatements.html>`_ view in PostgreSQL which tracks statistics about query speed.

This view can trace queries to originating tenants in a multi-tenant application, which helps for deciding when to do :ref:`tenant_isolation`.

+----------------+--------+---------------------------------------------------------+
| Name           | Type   | Description                                             |
+================+========+=========================================================+
| queryid        | bigint | identifier (good for pg_stat_statements joins)          |
+----------------+--------+---------------------------------------------------------+
| userid         | oid    | user who ran the query                                  |
+----------------+--------+---------------------------------------------------------+
| dbid           | oid    | database instance of coordinator                        |
+----------------+--------+---------------------------------------------------------+
| query          | text   | anonymized query string                                 |
+----------------+--------+---------------------------------------------------------+
| executor       | text   | Citus :ref:`executor <distributed_query_executor>` used:|
|                |        | adaptive, or insert-select                              |
+----------------+--------+---------------------------------------------------------+
| partition_key  | text   | value of distribution column in router-executed queries,|
|                |        | else NULL                                               |
+----------------+--------+---------------------------------------------------------+
| calls          | bigint | number of times the query was run                       |
+----------------+--------+---------------------------------------------------------+

.. code-block:: sql

  -- create and populate distributed table
  create table foo ( id int );
  select create_distributed_table('foo', 'id');
  insert into foo select generate_series(1,100);

  -- enable stats
  -- pg_stat_statements must be in shared_preload libraries
  create extension pg_stat_statements;

  select count(*) from foo;
  select * from foo where id = 42;

  select * from citus_stat_statements;

Results:

::

  -[ RECORD 1 ]-+----------------------------------------------
  queryid       | -909556869173432820
  userid        | 10
  dbid          | 13340
  query         | insert into foo select generate_series($1,$2)
  executor      | insert-select
  partition_key |
  calls         | 1
  -[ RECORD 2 ]-+----------------------------------------------
  queryid       | 3919808845681956665
  userid        | 10
  dbid          | 13340
  query         | select count(*) from foo;
  executor      | adaptive
  partition_key |
  calls         | 1
  -[ RECORD 3 ]-+----------------------------------------------
  queryid       | 5351346905785208738
  userid        | 10
  dbid          | 13340
  query         | select * from foo where id = $1
  executor      | adaptive
  partition_key | 42
  calls         | 1

Caveats:

* The stats data is not replicated, and won't survive database crashes or failover
* Tracks a limited number of queries, set by the ``pg_stat_statements.max`` GUC (default 5000)
* To truncate the table, use the ``citus_stat_statements_reset()`` function

Distributed Query Activity
~~~~~~~~~~~~~~~~~~~~~~~~~~

In some situations, queries might get blocked on row-level locks on one of the shards on a worker node. If that happens then those queries would not show up in `pg_locks <https://www.postgresql.org/docs/current/static/view-pg-locks.html>`_ on the Citus coordinator node.

Citus provides special views to watch queries and locks throughout the cluster, including shard-specific queries used internally to build results for distributed queries.

* **citus_dist_stat_activity**: shows the distributed queries that are executing on all nodes. A superset of ``pg_stat_activity``, usable wherever the latter is.
* **citus_worker_stat_activity**: shows queries on workers, including fragment queries against individual shards.
* **citus_lock_waits**: Blocked queries throughout the cluster.

The first two views include all columns of `pg_stat_activity <https://www.postgresql.org/docs/current/static/monitoring-stats.html#PG-STAT-ACTIVITY-VIEW>`_ plus the host/port of the worker that initiated the query and the host/port of the coordinator node of the cluster.

For example, consider counting the rows in a distributed table:

.. code-block:: postgres

   -- run from worker on localhost:9701

   SELECT count(*) FROM users_table;

We can see the query appear in ``citus_dist_stat_activity``:

.. code-block:: postgres

   SELECT * FROM citus_dist_stat_activity;

   -[ RECORD 1 ]----------+----------------------------------
   query_hostname         | localhost
   query_hostport         | 9701
   master_query_host_name | localhost
   master_query_host_port | 9701
   transaction_number     | 1
   transaction_stamp      | 2018-10-05 13:27:20.691907+03
   datid                  | 12630
   datname                | postgres
   pid                    | 23723
   usesysid               | 10
   usename                | citus
   application_name       | psql
   client_addr            | 
   client_hostname        | 
   client_port            | -1
   backend_start          | 2018-10-05 13:27:14.419905+03
   xact_start             | 2018-10-05 13:27:16.362887+03
   query_start            | 2018-10-05 13:27:20.682452+03
   state_change           | 2018-10-05 13:27:20.896546+03
   wait_event_type        | Client
   wait_event             | ClientRead
   state                  | idle in transaction
   backend_xid            | 
   backend_xmin           | 
   query                  | SELECT count(*) FROM users_table;
   backend_type           | client backend

This query requires information from all shards. Some of the information is in shard ``users_table_102038`` which happens to be stored in localhost:9700. We can see a query accessing the shard by looking at the ``citus_worker_stat_activity`` view:

.. code-block:: postgres

   SELECT * FROM citus_worker_stat_activity;

   -[ RECORD 1 ]----------+-----------------------------------------------------------------------------------------
   query_hostname         | localhost
   query_hostport         | 9700
   master_query_host_name | localhost
   master_query_host_port | 9701
   transaction_number     | 1
   transaction_stamp      | 2018-10-05 13:27:20.691907+03
   datid                  | 12630
   datname                | postgres
   pid                    | 23781
   usesysid               | 10
   usename                | citus
   application_name       | citus
   client_addr            | ::1
   client_hostname        | 
   client_port            | 51773
   backend_start          | 2018-10-05 13:27:20.75839+03
   xact_start             | 2018-10-05 13:27:20.84112+03
   query_start            | 2018-10-05 13:27:20.867446+03
   state_change           | 2018-10-05 13:27:20.869889+03
   wait_event_type        | Client
   wait_event             | ClientRead
   state                  | idle in transaction
   backend_xid            | 
   backend_xmin           | 
   query                  | COPY (SELECT count(*) AS count FROM users_table_102038 users_table WHERE true) TO STDOUT
   backend_type           | client backend

The ``query`` field shows data being copied out of the shard to be counted.

.. note::

  If a router query (e.g. single-tenant in a multi-tenant application, ``SELECT * FROM table WHERE tenant_id = X``) is executed without a transaction block, then master_query_host_name and master_query_host_port columns will be NULL in citus_worker_stat_activity.

To see how ``citus_lock_waits`` works, we can generate a locking situation manually. First we'll set up a test table from the coordinator:

.. code-block:: postgres

   CREATE TABLE numbers AS
     SELECT i, 0 AS j FROM generate_series(1,10) AS i;
   SELECT create_distributed_table('numbers', 'i');

Then, using two sessions on the coordinator, we can run this sequence of statements:

.. code-block:: postgres

   -- session 1                           -- session 2
   -------------------------------------  -------------------------------------
   BEGIN;
   UPDATE numbers SET j = 2 WHERE i = 1;
                                          BEGIN;
                                          UPDATE numbers SET j = 3 WHERE i = 1;
                                          -- (this blocks)

The ``citus_lock_waits`` view shows the situation.

.. code-block:: postgres

   SELECT * FROM citus_lock_waits;

   -[ RECORD 1 ]-------------------------+----------------------------------------
   waiting_pid                           | 88624
   blocking_pid                          | 88615
   blocked_statement                     | UPDATE numbers SET j = 3 WHERE i = 1;
   current_statement_in_blocking_process | UPDATE numbers SET j = 2 WHERE i = 1;
   waiting_node_id                       | 0
   blocking_node_id                      | 0
   waiting_node_name                     | coordinator_host
   blocking_node_name                    | coordinator_host
   waiting_node_port                     | 5432
   blocking_node_port                    | 5432

In this example the queries originated on the coordinator, but the view can also list locks between queries originating on workers.

Tables on all Nodes
-------------------

Citus has other informational tables and views which are accessible on all nodes, not just the coordinator.

.. _pg_dist_authinfo:

Connection Credentials Table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::

  This table is a part of Citus Enterprise Edition. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

The ``pg_dist_authinfo`` table holds authentication parameters used by Citus nodes to connect to one another.

+----------+---------+-------------------------------------------------+
| Name     | Type    | Description                                     |
+==========+=========+=================================================+
| nodeid   | integer | Node id from :ref:`pg_dist_node`, or 0, or -1   |
+----------+---------+-------------------------------------------------+
| rolename | name    | Postgres role                                   |
+----------+---------+-------------------------------------------------+
| authinfo | text    | Space-separated libpq connection parameters     |
+----------+---------+-------------------------------------------------+

Upon beginning a connection, a node consults the table to see whether a row with the destination ``nodeid`` and desired ``rolename`` exists. If so, the node includes the corresponding ``authinfo`` string in its libpq connection. A common example is to store a password, like ``'password=abc123'``, but you can review the `full list <https://www.postgresql.org/docs/current/static/libpq-connect.html#LIBPQ-PARAMKEYWORDS>`_ of possibilities.

The parameters in ``authinfo`` are space-separated, in the form ``key=val``. To write an empty value, or a value containing spaces, surround it with single quotes, e.g., ``keyword='a value'``. Single quotes and backslashes within the value must be escaped with a backslash, i.e., ``\'`` and ``\\``.

The ``nodeid`` column can also take the special values 0 and -1, which mean *all nodes* or *loopback connections*, respectively. If, for a given node, both specific and all-node rules exist, the specific rule has precedence.

::

    SELECT * FROM pg_dist_authinfo;

     nodeid | rolename | authinfo
    --------+----------+-----------------
        123 | jdoe     | password=abc123
    (1 row)

Connection Pooling Credentials
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::

  This table is a part of Citus Enterprise Edition. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

If you want to use a connection pooler to connect to a node, you can specify the pooler options using ``pg_dist_poolinfo``. This metadata table holds the host, port and database name for Citus to use when connecting to a node through a pooler.

If pool information is present, Citus will try to use these values instead of setting up a direct connection. The pg_dist_poolinfo information in this case supersedes :ref:`pg_dist_node <pg_dist_node>`.

+----------+---------+---------------------------------------------------+
| Name     | Type    | Description                                       |
+==========+=========+===================================================+
| nodeid   | integer | Node id from :ref:`pg_dist_node`                  |
+----------+---------+---------------------------------------------------+
| poolinfo | text    | Space-separated parameters: host, port, or dbname |
+----------+---------+---------------------------------------------------+

.. note::

   In some situations Citus ignores the settings in pg_dist_poolinfo. For instance :ref:`Shard rebalancing <shard_rebalancing>` is not compatible with connection poolers such as pgbouncer. In these scenarios Citus will use a direct connection.

.. code-block:: sql

   -- how to connect to node 1 (as identified in pg_dist_node)

   INSERT INTO pg_dist_poolinfo (nodeid, poolinfo)
        VALUES (1, 'host=127.0.0.1 port=5433');
