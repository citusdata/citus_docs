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
|                |                      | | * postgresql streaming replication:  's'                                |
|                |                      | | * two-phase commit (for reference tables): 't'                          |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_partition;
     logicalrelid  | partmethod |                                                        partkey                                                         | colocationid | repmodel 
    ---------------+------------+------------------------------------------------------------------------------------------------------------------------+--------------+----------
     github_events | h          | {VAR :varno 1 :varattno 4 :vartype 20 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnoold 1 :varoattno 4 :location -1} |            2 | s
     (1 row)

.. _pg_dist_shard:

Shard table
~~~~~~~~~~~~~~~~~

The pg_dist_shard table stores metadata about individual shards of a table. This includes information about which distributed table the shard belongs to and statistics about the distribution column for that shard. In case of hash distributed tables, they are hash token ranges assigned to that shard. These statistics are used for pruning away unrelated shards during SELECT queries.

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
| shardminvalue  |            text      | | For hash distributed tables, minimum hash token value assigned to that  |
|                |                      | | shard (inclusive).                                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardmaxvalue  |            text      | | For hash distributed tables, maximum hash token value assigned to that  |
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

.. _citus_shards:

Shard information view
~~~~~~~~~~~~~~~~~~~~~~

In addition to the low-level shard metadata table described above, Citus provides a ``citus_shards`` view to easily check:

* Where each shard is (node, and port),
* What kind of table it belongs to, and
* Its size

This view helps you inspect shards to find, among other things, any size imbalances across nodes.

.. code-block:: sql

  SELECT * FROM citus_shards;

::

  .
   table_name | shardid | shard_name   | citus_table_type | colocation_id | nodename  | nodeport | shard_size
  ------------+---------+--------------+------------------+---------------+-----------+----------+------------
   dist       |  102170 | dist_102170  | distributed      |            34 | localhost |     9701 |   90677248
   dist       |  102171 | dist_102171  | distributed      |            34 | localhost |     9702 |   90619904
   dist       |  102172 | dist_102172  | distributed      |            34 | localhost |     9701 |   90701824
   dist       |  102173 | dist_102173  | distributed      |            34 | localhost |     9702 |   90693632
   ref        |  102174 | ref_102174   | reference        |             2 | localhost |     9701 |       8192
   ref        |  102174 | ref_102174   | reference        |             2 | localhost |     9702 |       8192
   dist2      |  102175 | dist2_102175 | distributed      |            34 | localhost |     9701 |     933888
   dist2      |  102176 | dist2_102176 | distributed      |            34 | localhost |     9702 |     950272
   dist2      |  102177 | dist2_102177 | distributed      |            34 | localhost |     9701 |     942080
   dist2      |  102178 | dist2_102178 | distributed      |            34 | localhost |     9702 |     933888

The colocation_id refers to the :ref:`colocation group <colocation_group_table>`. For more info about citus_table_type, see :ref:`table_types`.

.. _placements:

Shard placement table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pg_dist_placement table tracks the location of shards on worker nodes. Each shard assigned to a specific node is called a shard placement. This table stores information about the health and location of each shard placement.

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
| shardlength    |       bigint         | | For hash distributed tables, zero.                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| groupid        |         int          | | Identifier used to denote a group of one primary server and zero or more|
|                |                      | | secondary servers.                                                      |
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

  That information is now available by joining pg_dist_placement with :ref:`pg_dist_node <pg_dist_node>` on the groupid. For compatibility Citus still provides pg_dist_shard_placement as a view. However, we recommend using the new, more normalized, tables when possible.


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
|                  |                      | | secondary servers. By default it is the same as the nodeid.             |
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

.. _citus_tables:

Citus tables view
~~~~~~~~~~~~~~~~~

The citus_tables view shows a summary of all tables managed by Citus (distributed and reference tables). The view combines information from Citus metadata tables for an easy, human-readable overview of these table properties:

* :ref:`Table type <table_types>`
* :ref:`Distribution column <dist_column>`
* :ref:`Colocation group <colocation_groups>` id
* Human-readable size
* Shard count
* Owner (database user)
* Access method (heap or :ref:`columnar <columnar>`)

Here's an example:

.. code-block:: sql

  SELECT * FROM citus_tables;

::

  ┌────────────┬──────────────────┬─────────────────────┬───────────────┬────────────┬─────────────┬─────────────┬───────────────┐
  │ table_name │ citus_table_type │ distribution_column │ colocation_id │ table_size │ shard_count │ table_owner │ access_method │
  ├────────────┼──────────────────┼─────────────────────┼───────────────┼────────────┼─────────────┼─────────────┼───────────────┤
  │ foo.test   │ distributed      │ test_column         │             1 │ 0 bytes    │          32 │ citus       │ heap          │
  │ ref        │ reference        │ <none>              │             2 │ 24 GB      │           1 │ citus       │ heap          │
  │ test       │ distributed      │ id                  │             1 │ 248 TB     │          32 │ citus       │ heap          │
  └────────────┴──────────────────┴─────────────────────┴───────────────┴────────────┴─────────────┴─────────────┴───────────────┘

.. _time_partitions:

Time partitions view
~~~~~~~~~~~~~~~~~~~~

Citus provides UDFs to manage partitions for the :ref:`timeseries` use case.
It also maintains a ``time_partitions`` view to inspect the partitions it
manages.

Columns:

* **parent_table** the table which is partitioned
* **partition_column** the column on which the parent table is partitioned
* **partition** the name of a partition table
* **from_value** lower bound in time for rows in this partition
* **to_value** upper bound in time for rows in this partition
* **access_method** ``heap`` for row-based storage, and ``columnar`` for columnar storage

.. code-block:: postgresql

   SELECT * FROM time_partitions;

::

   ┌────────────────────────┬──────────────────┬─────────────────────────────────────────┬─────────────────────┬─────────────────────┬───────────────┐
   │      parent_table      │ partition_column │                partition                │     from_value      │      to_value       │ access_method │
   ├────────────────────────┼──────────────────┼─────────────────────────────────────────┼─────────────────────┼─────────────────────┼───────────────┤
   │ github_columnar_events │ created_at       │ github_columnar_events_p2015_01_01_0000 │ 2015-01-01 00:00:00 │ 2015-01-01 02:00:00 │ columnar      │
   │ github_columnar_events │ created_at       │ github_columnar_events_p2015_01_01_0200 │ 2015-01-01 02:00:00 │ 2015-01-01 04:00:00 │ columnar      │
   │ github_columnar_events │ created_at       │ github_columnar_events_p2015_01_01_0400 │ 2015-01-01 04:00:00 │ 2015-01-01 06:00:00 │ columnar      │
   │ github_columnar_events │ created_at       │ github_columnar_events_p2015_01_01_0600 │ 2015-01-01 06:00:00 │ 2015-01-01 08:00:00 │ heap          │
   └────────────────────────┴──────────────────┴─────────────────────────────────────────┴─────────────────────┴─────────────────────┴───────────────┘

.. _colocation_group_table:

Co-location group table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The pg_dist_colocation table contains information about which tables' shards should be placed together, or :ref:`co-located <colocation>`. When two tables are in the same co-location group, Citus ensures shards with the same partition values will be placed on the same worker nodes. This enables join optimizations, certain distributed rollups, and foreign key support. Shard co-location is inferred when the shard counts, and partition column types all match between two tables; however, a custom co-location group may be specified when creating a distributed table, if so desired.

+-----------------------------+----------------------+---------------------------------------------------------------------------+
|      Name                   |         Type         |       Description                                                         |
+=============================+======================+===========================================================================+
| colocationid                |         int          | | Unique identifier for the co-location group this row corresponds to.    |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| shardcount                  |         int          | | Shard count for all tables in this co-location group                    |
+-----------------------------+----------------------+---------------------------------------------------------------------------+
| replicationfactor           |         int          | | Replication factor for all tables in this co-location group.            |
|                             |                      | | (Deprecated)                                                            |
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
                 2 |         32 |                 1 |                     20 |                           0
      (1 row)

.. _pg_dist_rebalance_strategy:

Rebalancer strategy table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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
| improvement_threshold          |         float4       | | Determines when moving a shard is worth it during a rebalance.          |
|                                |                      | | The rebalancer will move a shard when the ratio of the improvement with |
|                                |                      | | the shard move to the improvement without crosses the threshold. This   |
|                                |                      | | is most useful with the by_disk_size strategy.                          |
+--------------------------------+----------------------+---------------------------------------------------------------------------+

A Citus installation ships with these strategies in the table:

.. code-block:: postgres

    SELECT * FROM pg_dist_rebalance_strategy;

::

    -[ RECORD 1 ]------------------+---------------------------------
    name                           | by_shard_count
    default_strategy               | t
    shard_cost_function            | citus_shard_cost_1
    node_capacity_function         | citus_node_capacity_1
    shard_allowed_on_node_function | citus_shard_allowed_on_node_true
    default_threshold              | 0
    minimum_threshold              | 0
    improvement_threshold          | 0
    -[ RECORD 2 ]------------------+---------------------------------
    name                           | by_disk_size
    default_strategy               | f
    shard_cost_function            | citus_shard_cost_by_disk_size
    node_capacity_function         | citus_node_capacity_1
    shard_allowed_on_node_function | citus_shard_allowed_on_node_true
    default_threshold              | 0.1
    minimum_threshold              | 0.01
    improvement_threshold          | 0.5

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

  The citus_stat_statements view is a part of our :ref:`cloud_topic` only.

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

.. _dist_query_activity:

Distributed Query Activity
~~~~~~~~~~~~~~~~~~~~~~~~~~

In some situations, queries might get blocked on row-level locks on one of the shards on a worker node. If that happens then those queries would not show up in `pg_locks <https://www.postgresql.org/docs/current/static/view-pg-locks.html>`_ on the Citus coordinator node.

Citus provides special views to watch queries and locks throughout the cluster, including shard-specific queries used internally to build results for distributed queries.

* **citus_stat_activity**: shows the distributed queries that are executing on all nodes. A superset of ``pg_stat_activity``, usable wherever the latter is.
* **citus_dist_stat_activity**: the same as ``citus_stat_activity`` but restricted to distributed queries only, and excluding Citus fragment queries.
* **citus_lock_waits**: Blocked queries throughout the cluster.

The first two views include all columns of `pg_stat_activity <https://www.postgresql.org/docs/current/static/monitoring-stats.html#PG-STAT-ACTIVITY-VIEW>`_ plus the global PID of the worker that initiated the query.

For example, consider counting the rows in a distributed table:

.. code-block:: postgres

   -- run in one session
   -- (with a pg_sleep so we can see it)

   SELECT count(*), pg_sleep(3) FROM users_table;

We can see the query appear in ``citus_dist_stat_activity``:

.. code-block:: postgres

   -- run in another session

   SELECT * FROM citus_dist_stat_activity;

   -[ RECORD 1 ]----+-------------------------------------------
   global_pid       | 10000012199
   nodeid           | 1
   is_worker_query  | f
   datid            | 13724
   datname          | postgres
   pid              | 12199
   leader_pid       |
   usesysid         | 10
   usename          | postgres
   application_name | psql
   client_addr      |
   client_hostname  |
   client_port      | -1
   backend_start    | 2022-03-23 11:30:00.533991-05
   xact_start       | 2022-03-23 19:35:28.095546-05
   query_start      | 2022-03-23 19:35:28.095546-05
   state_change     | 2022-03-23 19:35:28.09564-05
   wait_event_type  | Timeout
   wait_event       | PgSleep
   state            | active
   backend_xid      |
   backend_xmin     | 777
   query_id         |
   query            | SELECT count(*), pg_sleep(3) FROM users_table;
   backend_type     | client backend

The ``citus_dist_stat_activity`` view hides internal Citus fragment queries. To
see those, we can use the more detailed ``citus_stat_activity`` view. For
instance, the previous ``count(*)`` query requires information from all shards.
Some of the information is in shard ``users_table_102039``, which is visible in
the query below.

.. code-block:: postgres

   SELECT * FROM citus_stat_activity;

   -[ RECORD 1 ]----+-----------------------------------------------------------------------
   global_pid       | 10000012199
   nodeid           | 1
   is_worker_query  | f
   datid            | 13724
   datname          | postgres
   pid              | 12199
   leader_pid       |
   usesysid         | 10
   usename          | postgres
   application_name | psql
   client_addr      |
   client_hostname  |
   client_port      | -1
   backend_start    | 2022-03-23 11:30:00.533991-05
   xact_start       | 2022-03-23 19:32:18.260803-05
   query_start      | 2022-03-23 19:32:18.260803-05
   state_change     | 2022-03-23 19:32:18.260821-05
   wait_event_type  | Timeout
   wait_event       | PgSleep
   state            | active
   backend_xid      |
   backend_xmin     | 777
   query_id         |
   query            | SELECT count(*), pg_sleep(3) FROM users_table;
   backend_type     | client backend
   -[ RECORD 2 ]----------+-----------------------------------------------------------------------------------------
   global_pid       | 10000012199
   nodeid           | 1
   is_worker_query  | t
   datid            | 13724
   datname          | postgres
   pid              | 12725
   leader_pid       |
   usesysid         | 10
   usename          | postgres
   application_name | citus_internal gpid=10000012199
   client_addr      | 127.0.0.1
   client_hostname  |
   client_port      | 44106
   backend_start    | 2022-03-23 19:29:53.377573-05
   xact_start       |
   query_start      | 2022-03-23 19:32:18.278121-05
   state_change     | 2022-03-23 19:32:18.278281-05
   wait_event_type  | Client
   wait_event       | ClientRead
   state            | idle
   backend_xid      |
   backend_xmin     |
   query_id         |
   query            | SELECT count(*) AS count FROM public.users_table_102039 users WHERE true
   backend_type     | client backend

The ``query`` field shows rows being counted in shard 102039.

Here are examples of useful queries you can build using
``citus_stat_activity``:

.. code-block:: postgres

  -- active queries' wait events

  SELECT query, wait_event_type, wait_event
    FROM citus_stat_activity
   WHERE state='active';

  -- active queries' top wait events

  SELECT wait_event, wait_event_type, count(*)
    FROM citus_stat_activity
   WHERE state='active'
   GROUP BY wait_event, wait_event_type
   ORDER BY count(*) desc;

  -- total internal connections generated per node by Citus

  SELECT nodeid, count(*)
    FROM citus_stat_activity
   WHERE is_worker_query
   GROUP BY nodeid;

The next view is ``citus_lock_waits``. To see how it works, we can generate a locking situation manually. First we'll set up a test table from the coordinator:

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

   -[ RECORD 1 ]-------------------------+--------------------------------------
   waiting_gpid                          | 10000011981
   blocking_gpid                         | 10000011979
   blocked_statement                     | UPDATE numbers SET j = 3 WHERE i = 1;
   current_statement_in_blocking_process | UPDATE numbers SET j = 2 WHERE i = 1;
   waiting_nodeid                        | 1
   blocking_nodeid                       | 1

In this example the queries originated on the coordinator, but the view can also list locks between queries originating on workers.

Tables on all Nodes
-------------------

Citus has other informational tables and views which are accessible on all nodes, not just the coordinator.

.. _pg_dist_authinfo:

Connection Credentials Table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::

  This table is a part of our :ref:`cloud_topic` only.

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

  This table is a part of our :ref:`cloud_topic` only.

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
