Reference
#########

.. _citus_sql_reference:

Citus SQL Support
=================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus supports all SQL queries on distributed tables, with only these exceptions:

* Correlated subqueries
* `Recursive <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_/`modifying <https://www.postgresql.org/docs/current/static/queries-with.html#QUERIES-WITH-MODIFYING>`_ CTEs
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_
* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_
* `Window functions <https://www.postgresql.org/docs/current/static/tutorial-window.html>`_ that do not include the distribution column in PARTITION BY

Furthermore, in :ref:`mt_use_case` when queries are filtered by table :ref:`dist_column` to a single tenant then all SQL features work, including the ones above.

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

.. _workarounds:

SQL Workarounds
===============

Before attempting workarounds consider whether Citus is appropriate for your
situation. Citus' current version works well for :ref:`real-time analytics and
multi-tenant use cases. <when_to_use_citus>`

Citus supports all SQL statements in the multi-tenant use-case. Even in the real-time analytics use-cases, with queries that span across nodes, Citus supports the majority of statements. The few types of unsupported queries are listed in :ref:`unsupported` Many of the unsupported features have workarounds; below are a number of the most useful.

.. _join_local_dist:

JOIN a local and a distributed table
------------------------------------

Attempting to execute a JOIN between a local table "local" and a distributed table "dist" causes an error:

.. code-block:: sql

  SELECT * FROM local JOIN dist USING (id);

  /*
  ERROR:  relation local is not distributed
  STATEMENT:  SELECT * FROM local JOIN dist USING (id);
  ERROR:  XX000: relation local is not distributed
  LOCATION:  DistributedTableCacheEntry, metadata_cache.c:711
  */

Although you can't join such tables directly, by wrapping the local table in a subquery or CTE you can make Citus' recursive query planner copy the local table data to worker nodes. By colocating the data this allows the query to proceed.

.. code-block:: sql

  -- either

  SELECT *
    FROM (SELECT * FROM local) AS x
    JOIN dist USING (id);

  -- or

  WITH x AS (SELECT * FROM local)
  SELECT * FROM x
  JOIN dist USING (id);

Remember that the coordinator will send the results in the subquery or CTE to all workers which require it for processing. Thus it's best to either add the most specific filters and limits to the inner query as possible, or else aggregate the table. That reduces the network overhead which such a query can cause. More about this in :ref:`subquery_perf`.

Temp Tables: the Last Resort
----------------------------

There are still a few queries that are :ref:`unsupported <unsupported>` even with the use of push-pull execution via subqueries. One of them is running window functions that partition by a non-distribution column.

Suppose we have a table called :code:`github_events`, distributed by the column :code:`user_id`. Then the following window function will not work:

.. code-block:: sql

  -- this won't work

  SELECT repo_id, org->'id' as org_id, count(*)
    OVER (PARTITION BY repo_id) -- repo_id is not distribution column
    FROM github_events
   WHERE repo_id IN (8514, 15435, 19438, 21692);

There is another trick though. We can pull the relevant information to the coordinator as a temporary table:

.. code-block:: sql

  -- grab the data, minus the aggregate, into a local table

  CREATE TEMP TABLE results AS (
    SELECT repo_id, org->'id' as org_id
      FROM github_events
     WHERE repo_id IN (8514, 15435, 19438, 21692)
  );

  -- now run the aggregate locally

  SELECT repo_id, org_id, count(*)
    OVER (PARTITION BY repo_id)
    FROM results;

Creating a temporary table on the coordinator is a last resort. It is limited by the disk size and CPU of the node.

.. _user_defined_functions:

Citus Utility Function Reference
================================

This section contains reference information for the User Defined Functions provided by Citus. These functions help in providing additional distributed functionality to Citus other than the standard SQL commands.

Table and Shard DDL
-------------------
.. _create_distributed_table:

create_distributed_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The create_distributed_table() function is used to define a distributed table
and create its shards if it's a hash-distributed table. This function takes in a
table name, the distribution column and an optional distribution method and inserts
appropriate metadata to mark the table as distributed. The function defaults to
'hash' distribution if no distribution method is specified. If the table is
hash-distributed, the function also creates worker shards based on the shard
count and shard replication factor configuration values. If the table contains
any rows, they are automatically distributed to worker nodes.

This function replaces usage of master_create_distributed_table() followed by
master_create_worker_shards().

Arguments
************************

**table_name:** Name of the table which needs to be distributed.

**distribution_column:** The column on which the table is to be distributed.

**distribution_method:** (Optional) The method according to which the table is
to be distributed. Permissible values are append or hash, and defaults to 'hash'.

**colocate_with:** (Optional) include current table in the co-location group of another table. By default tables are co-located when they are distributed by columns of the same type, have the same shard count, and have the same replication factor. Possible values for :code:`colocate_with` are :code:`default`, :code:`none` to start a new co-location group, or the name of another table to co-locate with that table.  (See :ref:`colocation_groups`.)

Return Value
********************************

N/A

Example
*************************
This example informs the database that the github_events table should be distributed by hash on the repo_id column.

::

  SELECT create_distributed_table('github_events', 'repo_id');

  -- alternatively, to be more explicit:
  SELECT create_distributed_table('github_events', 'repo_id',
                                  colocate_with => 'github_repo');

For more examples, see :ref:`ddl`.

create_reference_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
.. _create_reference_table:

The create_reference_table() function is used to define a small reference or
dimension table. This function takes in a table name, and creates a distributed
table with just one shard, replicated to every worker node. The distribution
column is unimportant since the UDF only creates one shard for the table.

Arguments
************************

**table_name:** Name of the small dimension or reference table which needs to be distributed.


Return Value
********************************

N/A

Example
*************************
This example informs the database that the nation table should be defined as a
reference table

::

	SELECT create_reference_table('nation');

upgrade_to_reference_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
.. _upgrade_to_reference_table:

The upgrade_to_reference_table() function takes an existing distributed table which has a shard count of one, and upgrades it to be a recognized reference table. After calling this function, the table will be as if it had been created with :ref:`create_reference_table <create_reference_table>`.

Arguments
************************

**table_name:** Name of the distributed table (having shard count = 1) which will be distributed as a reference table.

Return Value
********************************

N/A

Example
*************************

This example informs the database that the nation table should be defined as a
reference table

::

	SELECT upgrade_to_reference_table('nation');

master_create_distributed_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
.. _master_create_distributed_table:

.. note::
   This function is deprecated, and replaced by :ref:`create_distributed_table <create_distributed_table>`.

The master_create_distributed_table() function is used to define a distributed
table. This function takes in a table name, the distribution column and
distribution method and inserts appropriate metadata to mark the table as
distributed.


Arguments
************************

**table_name:** Name of the table which needs to be distributed.

**distribution_column:** The column on which the table is to be distributed.

**distribution_method:** The method according to which the table is to be distributed. Permissible values are append or hash.

Return Value
********************************

N/A

Example
*************************
This example informs the database that the github_events table should be distributed by hash on the repo_id column.

::

	SELECT master_create_distributed_table('github_events', 'repo_id', 'hash');


master_create_worker_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
.. _master_create_worker_shards:

.. note::
   This function is deprecated, and replaced by :ref:`create_distributed_table <create_distributed_table>`.

The master_create_worker_shards() function creates a specified number of worker shards with the desired replication factor for a *hash* distributed table. While doing so, the function also assigns a portion of the hash token space (which spans between -2 Billion and 2 Billion) to each shard. Once all shards are created, this function saves all distributed metadata on the coordinator.

Arguments
*****************************

**table_name:** Name of hash distributed table for which shards are to be created.

**shard_count:** Number of shards to create.

**replication_factor:** Desired replication factor for each shard.

Return Value
**************************
N/A

Example
***************************

This example usage would create a total of 16 shards for the github_events table where each shard owns a portion of a hash token space and gets replicated on 2 workers.

::

	SELECT master_create_worker_shards('github_events', 16, 2);


master_create_empty_shard
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_create_empty_shard() function can be used to create an empty shard for an *append* distributed table. Behind the covers, the function first selects shard_replication_factor workers to create the shard on. Then, it connects to the workers and creates empty placements for the shard on the selected workers. Finally, the metadata is updated for these placements on the coordinator to make these shards visible to future queries. The function errors out if it is unable to create the desired number of shard placements.

Arguments
*********************

**table_name:** Name of the append distributed table for which the new shard is to be created.

Return Value
****************************

**shard_id:** The function returns the unique id assigned to the newly created shard.

Example
**************************

This example creates an empty shard for the github_events table. The shard id of the created shard is 102089.

::

    SELECT * from master_create_empty_shard('github_events');
     master_create_empty_shard
    ---------------------------
                    102089
    (1 row)

Table and Shard DML
-------------------

.. _master_append_table_to_shard:

master_append_table_to_shard
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_append_table_to_shard() function can be used to append a PostgreSQL table's contents to a shard of an *append* distributed table. Behind the covers, the function connects to each of the workers which have a placement of that shard and appends the contents of the table to each of them. Then, the function updates metadata for the shard placements on the basis of whether the append succeeded or failed on each of them.

If the function is able to successfully append to at least one shard placement, the function will return successfully. It will also mark any placement to which the append failed as INACTIVE so that any future queries do not consider that placement. If the append fails for all placements, the function quits with an error (as no data was appended). In this case, the metadata is left unchanged.

Arguments
************************

**shard_id:** Id of the shard to which the contents of the table have to be appended.

**source_table_name:** Name of the PostgreSQL table whose contents have to be appended.

**source_node_name:** DNS name of the node on which the source table is present ("source" node).

**source_node_port:** The port on the source worker node on which the database server is listening.

Return Value
****************************

**shard_fill_ratio:** The function returns the fill ratio of the shard which is defined as the ratio of the current shard size to the configuration parameter shard_max_size.

Example
******************

This example appends the contents of the github_events_local table to the shard having shard id 102089. The table github_events_local is present on the database running on the node master-101 on port number 5432. The function returns the ratio of the the current shard size to the maximum shard size, which is 0.1 indicating that 10% of the shard has been filled.

::

    SELECT * from master_append_table_to_shard(102089,'github_events_local','master-101', 5432);
     master_append_table_to_shard
    ------------------------------
                     0.100548
    (1 row)


master_apply_delete_command
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_apply_delete_command() function is used to delete shards which match the criteria specified by the delete command. This function deletes a shard only if all rows in the shard match the delete criteria. As the function uses shard metadata to decide whether or not a shard needs to be deleted, it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards of that table are deleted.

Behind the covers, this function connects to all the worker nodes which have shards matching the delete criteria and sends them a command to drop the selected shards. Then, the function updates the corresponding metadata on the coordinator. If the function is able to successfully delete a shard placement, then the metadata for it is deleted. If a particular placement could not be deleted, then it is marked as TO DELETE. The placements which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

Arguments
*********************

**delete_command:** valid `SQL DELETE <http://www.postgresql.org/docs/current/static/sql-delete.html>`_ command

Return Value
**************************

**deleted_shard_count:** The function returns the number of shards which matched the criteria and were deleted (or marked for deletion). Note that this is the number of shards and not the number of shard placements.

Example
*********************

The first example deletes all the shards for the github_events table since no delete criteria is specified. In the second example, only the shards matching the criteria (3 in this case) are deleted.

::

    SELECT * from master_apply_delete_command('DELETE FROM github_events');
     master_apply_delete_command
    -----------------------------
                               5
    (1 row)
 
    SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE review_date < ''2009-03-01''');
     master_apply_delete_command
    -----------------------------
                               3
    (1 row)

master_modify_multiple_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_modify_multiple_shards() function is used to run data modification statements which could span multiple shards. Depending on the value of citus.multi_shard_commit_protocol, the commit can be done in one- or two-phases.

Limitations:

* It cannot be called inside a transaction block
* It must be called with simple operator expressions only

Arguments
**********

**modify_query:** A simple DELETE or UPDATE query as a string.

Return Value
************

N/A

Example
********

::

  SELECT master_modify_multiple_shards(
    'DELETE FROM customer_delete_protocol WHERE c_custkey > 500 AND c_custkey < 500');

Metadata / Configuration Information
------------------------------------------------------------------------

.. _master_add_node:

master_add_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_add_node() function registers a new node addition in the cluster in
the Citus metadata table pg_dist_node. It also copies reference tables to the new node.

Arguments
************************

**node_name:** DNS name or IP address of the new node to be added.

**node_port:** The port on which PostgreSQL is listening on the worker node.

**group_id:** A group of one primary server and zero or more secondary
servers, relevant only for streaming replication.  Default 0

**node_role:** Whether it is 'primary' or 'secondary'. Default 'primary'

**node_cluster:** The cluster name. Default 'default'

Return Value
******************************

A tuple which represents a row from :ref:`pg_dist_node
<pg_dist_node>` table.


Example
***********************

::

    select * from master_add_node('new-node', 12345);
     nodeid | groupid | nodename | nodeport | noderack | hasmetadata | isactive | groupid | noderole | nodecluster
    --------+---------+----------+----------+----------+-------------+----------+---------+----------+ ------------
          7 |       7 | new-node |    12345 | default  | f           | t        |       0 | primary  | default
    (1 row)

.. _master_update_node:

master_update_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_update_node() function changes the hostname and port for a node registered in the Citus metadata table :ref:`pg_dist_node <pg_dist_node>`.

Arguments
************************

**node_id:** id from the pg_dist_node table.

**node_name:** updated DNS name or IP address for the node.

**node_port:** the port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

::

    select * from master_update_node(123, 'new-address', 5432);

.. _master_add_inactive_node:

master_add_inactive_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The :code:`master_add_inactive_node` function, similar to :ref:`master_add_node`,
registers a new node in :code:`pg_dist_node`. However it marks the new
node as inactive, meaning no shards will be placed there. Also it does
*not* copy reference tables to the new node.

Arguments
************************

**node_name:** DNS name or IP address of the new node to be added.

**node_port:** The port on which PostgreSQL is listening on the worker node.

**group_id:** A group of one primary server and zero or more secondary
servers, relevant only for streaming replication.  Default 0

**node_role:** Whether it is 'primary' or 'secondary'. Default 'primary'

**node_cluster:** The cluster name. Default 'default'

Return Value
******************************

A tuple which represents a row from :ref:`pg_dist_node <pg_dist_node>` table.

Example
***********************

::

    select * from master_add_inactive_node('new-node', 12345);
     nodeid | groupid | nodename | nodeport | noderack | hasmetadata | isactive | groupid | noderole | nodecluster
    --------+---------+----------+----------+----------+-------------+----------+---------+----------+ -------------
          7 |       7 | new-node |    12345 | default  | f           | f        |       0 | primary  | default
    (1 row)

master_activate_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The :code:`master_activate_node` function marks a node as active in the
Citus metadata table :code:`pg_dist_node` and copies reference tables to
the node. Useful for nodes added via :ref:`master_add_inactive_node`.

Arguments
************************

**node_name:** DNS name or IP address of the new node to be added.

**node_port:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

A tuple which represents a row from :ref:`pg_dist_node
<pg_dist_node>` table.

Example
***********************

::

    select * from master_activate_node('new-node', 12345);
     nodeid | groupid | nodename | nodeport | noderack | hasmetadata | isactive| noderole | nodecluster
    --------+---------+----------+----------+----------+-------------+---------+----------+ -------------
          7 |       7 | new-node |    12345 | default  | f           | t       | primary  | default
    (1 row)

master_disable_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The :code:`master_disable_node` function is the opposite of
:code:`master_activate_node`. It marks a node as inactive in
the Citus metadata table :code:`pg_dist_node`, removing it from
the cluster temporarily. The function also deletes all reference table
placements from the disabled node. To reactivate the node, just run
:code:`master_activate_node` again.

Arguments
************************

**node_name:** DNS name or IP address of the node to be disabled.

**node_port:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

::

    select * from master_disable_node('new-node', 12345);

.. _master_add_secondary_node:

master_add_secondary_node
$$$$$$$$$$$$$$$$$$$$$$$$$

The master_add_secondary_node() function registers a new secondary
node in the cluster for an existing primary node. It updates the Citus
metadata table pg_dist_node.

Arguments
************************

**node_name:** DNS name or IP address of the new node to be added.

**node_port:** The port on which PostgreSQL is listening on the worker node.

**primary_name:** DNS name or IP address of the primary node for this secondary.

**primary_port:** The port on which PostgreSQL is listening on the primary node.

**node_cluster:** The cluster name. Default 'default'

Return Value
******************************

A tuple which represents a row from :ref:`pg_dist_node <pg_dist_node>` table.

Example
***********************

::

    select * from master_add_secondary_node('new-node', 12345, 'primary-node', 12345);
     nodeid | groupid | nodename | nodeport | noderack | hasmetadata | isactive | noderole  | nodecluster
    --------+---------+----------+----------+----------+-------------+----------+-----------+-------------
          7 |       7 | new-node |    12345 | default  | f           | t        | secondary | default
    (1 row)


master_remove_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_remove_node() function removes the specified node from the
pg_dist_node metadata table. This function will error out if there
are existing shard placements on this node. Thus, before using this
function, the shards will need to be moved off that node.

Arguments
************************

**node_name:** DNS name of the node to be removed.

**node_port:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

::

    select master_remove_node('new-node', 12345);
     master_remove_node 
    --------------------
     
    (1 row)

master_get_active_worker_nodes
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_get_active_worker_nodes() function returns a list of active worker
host names and port numbers. Currently, the function assumes that all the worker
nodes in the pg_dist_node catalog table are active.

Arguments
************************

N/A

Return Value
******************************

List of tuples where each tuple contains the following information:

**node_name:** DNS name of the worker node

**node_port:** Port on the worker node on which the database server is listening

Example
***********************

::

    SELECT * from master_get_active_worker_nodes();
     node_name | node_port 
    -----------+-----------
     localhost |      9700
     localhost |      9702
     localhost |      9701

    (3 rows)

master_get_table_metadata
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_get_table_metadata() function can be used to return distribution related metadata for a distributed table. This metadata includes the relation id, storage type, distribution method, distribution column, replication count, maximum shard size and the shard placement policy for that table. Behind the covers, this function queries Citus metadata tables to get the required information and concatenates it into a tuple before returning it to the user.

Arguments
***********************

**table_name:** Name of the distributed table for which you want to fetch metadata.

Return Value
*********************************

A tuple containing the following information:

**logical_relid:** Oid of the distributed table. This values references the relfilenode column in the pg_class system catalog table.

**part_storage_type:** Type of storage used for the table. May be 't' (standard table), 'f' (foreign table) or 'c' (columnar table).

**part_method:** Distribution method used for the table. May be 'a' (append), or 'h' (hash).

**part_key:** Distribution column for the table.

**part_replica_count:** Current shard replication count.

**part_max_size:** Current maximum shard size in bytes.

**part_placement_policy:** Shard placement policy used for placing the table’s shards. May be 1 (local-node-first) or 2 (round-robin).

Example
*************************

The example below fetches and displays the table metadata for the github_events table.

::

    SELECT * from master_get_table_metadata('github_events’);
     logical_relid | part_storage_type | part_method | part_key | part_replica_count | part_max_size | part_placement_policy 
    ---------------+-------------------+-------------+----------+--------------------+---------------+-----------------------
             24180 | t                 | h           | repo_id  |                  2 |    1073741824 |                     2
    (1 row)

.. _get_shard_id:

get_shard_id_for_distribution_column
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus assigns every row of a distributed table to a shard based on the value of the row's distribution column and the table's method of distribution. In most cases the precise mapping is a low-level detail that the database administrator can ignore. However it can be useful to determine a row's shard, either for manual database maintenance tasks or just to satisfy curiosity. The :code:`get_shard_id_for_distribution_column` function provides this info for hash- and range-distributed tables as well as reference tables. It does not work for the append distribution.

Arguments
************************

**table_name:** The distributed table.

**distribution_value:** The value of the distribution column.

Return Value
******************************

The shard id Citus associates with the distribution column value for the given table.

Example
***********************

::

  SELECT get_shard_id_for_distribution_column('my_table', 4);

   get_shard_id_for_distribution_column
  --------------------------------------
                                 540007
  (1 row)

column_to_column_name
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Translates the :code:`partkey` column of :code:`pg_dist_partition` into a textual column name. This is useful to determine the distribution column of a distributed table.

For a more detailed discussion, see :ref:`finding_dist_col`.

Arguments
************************

**table_name:** The distributed table.

**column_var_text:** The value of :code:`partkey` in the :code:`pg_dist_partition` table.

Return Value
******************************

The name of :code:`table_name`'s distribution column.

Example
***********************

.. code-block:: postgresql

  -- get distribution column name for products table

  SELECT column_to_column_name(logicalrelid, partkey) AS dist_col_name
    FROM pg_dist_partition
   WHERE logicalrelid='products'::regclass;

Output:

::

  ┌───────────────┐
  │ dist_col_name │
  ├───────────────┤
  │ company_id    │
  └───────────────┘

citus_relation_size
$$$$$$$$$$$$$$$$$$$

Get the disk space used by all the shards of the specified distributed table. This includes the size of the "main fork," but excludes the visibility map and free space map for the shards.

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_relation_size('github_events'));

::

  pg_size_pretty
  --------------
  23 MB

citus_table_size
$$$$$$$$$$$$$$$$

Get the disk space used by all the shards of the specified distributed table, excluding indexes (but including TOAST, free space map, and visibility map).

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_table_size('github_events'));

::

  pg_size_pretty
  --------------
  37 MB

citus_total_relation_size
$$$$$$$$$$$$$$$$$$$$$$$$$

Get the total disk space used by the all the shards of the specified distributed table, including all indexes and TOAST data.

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_total_relation_size('github_events'));

::

  pg_size_pretty
  --------------
  73 MB

.. _cluster_management_functions:

Cluster Management And Repair Functions
----------------------------------------

master_copy_shard_placement
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

If a shard placement fails to be updated during a modification command or a DDL operation, then it gets marked as inactive. The master_copy_shard_placement function can then be called to repair an inactive shard placement using data from a healthy placement.

To repair a shard, the function first drops the unhealthy shard placement and recreates it using the schema on the coordinator. Once the shard placement is created, the function copies data from the healthy placement and updates the metadata to mark the new shard placement as healthy. This function ensures that the shard will be protected from any concurrent modifications during the repair.

Arguments
**********

**shard_id:** Id of the shard to be repaired.

**source_node_name:** DNS name of the node on which the healthy shard placement is present ("source" node).

**source_node_port:** The port on the source worker node on which the database server is listening.

**target_node_name:** DNS name of the node on which the invalid shard placement is present ("target" node).

**target_node_port:** The port on the target worker node on which the database server is listening.

Return Value
************

N/A

Example
********

The example below will repair an inactive shard placement of shard 12345 which is present on the database server running on 'bad_host' on port 5432. To repair it, it will use data from a healthy shard placement present on the server running on 'good_host' on port 5432.

::

    SELECT master_copy_shard_placement(12345, 'good_host', 5432, 'bad_host', 5432);

master_move_shard_placement
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

  The master_move_shard_placement function is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

This function moves a given shard (and shards co-located with it) from one node to another. It is typically used indirectly during shard rebalancing rather than being called directly by a database administrator.

There are two ways to move the data: blocking or nonblocking. The blocking approach means that during the move all modifications to the shard are paused. The second way, which avoids blocking shard writes, relies on Postgres 10 logical replication.

After a successful move operation, shards in the source node get deleted. If the move fails at any point, this function throws an error and leaves the source and target nodes unchanged.

Arguments
**********

**shard_id:** Id of the shard to be moved.

**source_node_name:** DNS name of the node on which the healthy shard placement is present ("source" node).

**source_node_port:** The port on the source worker node on which the database server is listening.

**target_node_name:** DNS name of the node on which the invalid shard placement is present ("target" node).

**target_node_port:** The port on the target worker node on which the database server is listening.

**shard_transfer_mode:** (Optional) Specify the method of replication, whether to use PostgreSQL logical replication or a cross-worker COPY command. The possible values are:

  * ``auto``: Require replica identity if logical replication is possible, otherwise use legacy behaviour (e.g. for shard repair, PostgreSQL 9.6). This is the default value.
  * ``force_logical``: Use logical replication even if the table doesn't have a replica identity. Any concurrent update/delete statements to the table will fail during replication.
  * ``block_writes``: Use COPY (blocking writes) for tables lacking primary key or replica identity.

Return Value
************

N/A

Example
********

::

    SELECT master_move_shard_placement(12345, 'from_host', 5432, 'to_host', 5432);

.. _rebalance_table_shards:

rebalance_table_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::
  The rebalance_table_shards function is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

The rebalance_table_shards() function moves shards of the given table to make them evenly distributed among the workers. The function first calculates the list of moves it needs to make in order to ensure that the cluster is balanced within the given threshold. Then, it moves shard placements one by one from the source node to the destination node and updates the corresponding shard metadata to reflect the move.

Arguments
**************************

**table_name:** The name of the table whose shards need to be rebalanced.

**threshold:** (Optional) A float number between 0.0 and 1.0 which indicates the maximum difference ratio of node utilization from average utilization. For example, specifying 0.1 will cause the shard rebalancer to attempt to balance all nodes to hold the same number of shards ±10%. Specifically, the shard rebalancer will try to converge utilization of all worker nodes to the (1 - threshold) * average_utilization ... (1 + threshold) * average_utilization range.

**max_shard_moves:** (Optional) The maximum number of shards to move.

**excluded_shard_list:** (Optional) Identifiers of shards which shouldn't be moved during the rebalance operation.

**shard_transfer_mode:** (Optional) Specify the method of replication, whether to use PostgreSQL logical replication or a cross-worker COPY command. The possible values are:

  * ``auto``: Require replica identity if logical replication is possible, otherwise use legacy behaviour (e.g. for shard repair, PostgreSQL 9.6). This is the default value.
  * ``force_logical``: Use logical replication even if the table doesn't have a replica identity. Any concurrent update/delete statements to the table will fail during replication.
  * ``block_writes``: Use COPY (blocking writes) for tables lacking primary key or replica identity.

Return Value
*********************************

N/A

Example
**************************

The example below will attempt to rebalance the shards of the github_events table within the default threshold.

::

	SELECT rebalance_table_shards('github_events');

This example usage will attempt to rebalance the github_events table without moving shards with id 1 and 2.

::

	SELECT rebalance_table_shards('github_events', excluded_shard_list:='{1,2}');


replicate_table_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::
  The replicate_table_shards function is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

The replicate_table_shards() function replicates the under-replicated shards of the given table. The function first calculates the list of under-replicated shards and locations from which they can be fetched for replication. The function then copies over those shards and updates the corresponding shard metadata to reflect the copy.

Arguments
*************************

**table_name:** The name of the table whose shards need to be replicated.

**shard_replication_factor:** (Optional) The desired replication factor to achieve for each shard.

**max_shard_copies:** (Optional) Maximum number of shards to copy to reach the desired replication factor.

**excluded_shard_list:** (Optional) Identifiers of shards which shouldn't be copied during the replication operation.

Return Value
***************************

N/A

Examples
**************************

The example below will attempt to replicate the shards of the github_events table to shard_replication_factor.

::

	SELECT replicate_table_shards('github_events');

This example will attempt to bring the shards of the github_events table to the desired replication factor with a maximum of 10 shard copies. This means that the rebalancer will copy only a maximum of 10 shards in its attempt to reach the desired replication factor.

::

	SELECT replicate_table_shards('github_events', max_shard_copies:=10);

.. _isolate_tenant_to_new_shard:

isolate_tenant_to_new_shard
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::
  The isolate_tenant_to_new_shard function is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

This function creates a new shard to hold rows with a specific single value in the distribution column. It is especially handy for the multi-tenant Citus use case, where a large tenant can be placed alone on its own shard and ultimately its own physical node.

For a more in-depth discussion, see :ref:`tenant_isolation`.

Arguments
*************************

**table_name:** The name of the table to get a new shard.

**tenant_id:** The value of the distribution column which will be assigned to the new shard.

**cascade_option:** (Optional) When set to "CASCADE," also isolates a shard from all tables in the current table's :ref:`colocation_groups`.

Return Value
***************************

**shard_id:** The function returns the unique id assigned to the newly created shard.

Examples
**************************

Create a new shard to hold the lineitems for tenant 135:

.. code-block:: postgresql

  SELECT isolate_tenant_to_new_shard('lineitem', 135);

::

  ┌─────────────────────────────┐
  │ isolate_tenant_to_new_shard │
  ├─────────────────────────────┤
  │                      102240 │
  └─────────────────────────────┘

.. _metadata_tables:

Metadata Tables Reference
==========================

Citus divides each distributed table into multiple logical shards based on the distribution column. The coordinator then maintains metadata tables to track statistics and information about the health and location of these shards. In this section, we describe each of these metadata tables and their schema. You can view and query these tables using SQL after logging into the coordinator node.

.. _partition_table:

Partition table
-----------------

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
|                |                      | | citus statement-based replication: 'c'                                  |
|                |                      | | postgresql streaming replication:  's'                                  |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_partition;
     logicalrelid  | partmethod |                                                        partkey                                                         | colocationid | repmodel 
    ---------------+------------+------------------------------------------------------------------------------------------------------------------------+--------------+----------
     github_events | h          | {VAR :varno 1 :varattno 4 :vartype 20 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnoold 1 :varoattno 4 :location -1} |            2 | c
     (1 row)

.. _pg_dist_shard:

Shard table
-----------------

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
---------------------------------------

The pg_dist_placement table tracks the location of shard replicas on worker nodes. Each replica of a shard assigned to a specific node is called a shard placement. This table stores information about the health and location of each shard placement.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| shardid        |       bigint         | | Shard identifier associated with this placement. This values references |
|                |                      | | the shardid column in the pg_dist_shard catalog table.                  |
+----------------+----------------------+---------------------------------------------------------------------------+ 
| shardstate     |         int          | | Describes the state of this placement. Different shard states are       |
|                |                      | | discussed in the section below.                                         |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardlength    |       bigint         | | For append distributed tables, the size of the shard placement on the   |
|                |                      | | worker node in bytes.                                                   |
|                |                      | | For hash distributed tables, zero.                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| placementid    |       bigint         | | Unique auto-generated identifier for each individual placement.         |
+----------------+----------------------+---------------------------------------------------------------------------+
| groupid        |         int          | | Identifier used to denote a group of one primary server and zero or more|
|                |                      | | secondary servers, when the streaming replication model is used.        |
+----------------+----------------------+---------------------------------------------------------------------------+

::

  SELECT * from pg_dist_placement;
    shardid | shardstate | shardlength | placementid | groupid
   ---------+------------+-------------+-------------+---------
     102008 |          1 |           0 |           1 |       1
     102008 |          1 |           0 |           2 |       2
     102009 |          1 |           0 |           3 |       2
     102009 |          1 |           0 |           4 |       3
     102010 |          1 |           0 |           5 |       3
     102010 |          1 |           0 |           6 |       4
     102011 |          1 |           0 |           7 |       4

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


Worker node table
---------------------------------------
.. _pg_dist_node:

The pg_dist_node table contains information about the worker nodes in the cluster. 

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| nodeid         |         int          | | Auto-generated identifier for an individual node.                       |
+----------------+----------------------+---------------------------------------------------------------------------+
| groupid        |         int          | | Identifier used to denote a group of one primary server and zero or more|
|                |                      | | secondary servers, when the streaming replication model is used. By     |
|                |                      | | default it is the same as the nodeid.                                   | 
+----------------+----------------------+---------------------------------------------------------------------------+
| nodename       |         text         | | Host Name or IP Address of the PostgreSQL worker node.                  |
+----------------+----------------------+---------------------------------------------------------------------------+
| nodeport       |         int          | | Port number on which the PostgreSQL worker node is listening.           |
+----------------+----------------------+---------------------------------------------------------------------------+
| noderack       |        text          | | (Optional) Rack placement information for the worker node.              |
+----------------+----------------------+---------------------------------------------------------------------------+
| hasmetadata    |        boolean       | | Reserved for internal use.                                              |
+----------------+----------------------+---------------------------------------------------------------------------+
| isactive       |        boolean       | | Whether the node is active accepting shard placements.                  |
+----------------+----------------------+---------------------------------------------------------------------------+
| noderole       |        text          | | Whether the node is a primary or secondary                              |
+----------------+----------------------+---------------------------------------------------------------------------+
| nodecluster    |        text          | | The name of the cluster containing this node                            |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_node;
     nodeid | groupid | nodename  | nodeport | noderack | hasmetadata | isactive | noderole | nodecluster
    --------+---------+-----------+----------+----------+-------------+----------+----------+ -------------
          1 |       1 | localhost |    12345 | default  | f           | t        | primary  | default
          2 |       2 | localhost |    12346 | default  | f           | t        | primary  | default
          3 |       3 | localhost |    12347 | default  | f           | t        | primary  | default
    (3 rows)

.. _colocation_group_table:

Co-location group table
---------------------------------------

The pg_dist_colocation table contains information about which tables' shards should be placed together, or :ref:`co-located <colocation>`. When two tables are in the same co-location group, Citus ensures shards with the same partition values will be placed on the same worker nodes. This enables join optimizations, certain distributed rollups, and foreign key support. Shard co-location is inferred when the shard counts, replication factors, and partition column types all match between two tables; however, a custom co-location group may be specified when creating a distributed table, if so desired.

+------------------------+----------------------+---------------------------------------------------------------------------+
|      Name              |         Type         |       Description                                                         |
+========================+======================+===========================================================================+
| colocationid           |         int          | | Unique identifier for the co-location group this row corresponds to.    |
+------------------------+----------------------+---------------------------------------------------------------------------+
| shardcount             |         int          | | Shard count for all tables in this co-location group                    |
+------------------------+----------------------+---------------------------------------------------------------------------+
| replicationfactor      |         int          | | Replication factor for all tables in this co-location group.            |
+------------------------+----------------------+---------------------------------------------------------------------------+
| distributioncolumntype |         oid          | | The type of the distribution column for all tables in this              |
|                        |                      | | co-location group.                                                      |
+------------------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_colocation;
      colocationid | shardcount | replicationfactor | distributioncolumntype 
     --------------+------------+-------------------+------------------------
                 2 |         32 |                 2 |                     20
      (1 row)


.. _configuration:

Configuration Reference
=======================

There are various configuration parameters that affect the behaviour of Citus. These include both standard PostgreSQL parameters and Citus specific parameters. To learn more about PostgreSQL configuration parameters, you can visit the `run time configuration <http://www.postgresql.org/docs/current/static/runtime-config.html>`_ section of PostgreSQL documentation.

The rest of this reference aims at discussing Citus specific configuration parameters. These parameters can be set similar to PostgreSQL parameters by modifying postgresql.conf or `by using the SET command <http://www.postgresql.org/docs/current/static/config-setting.html>`_.

As an example you can update a setting with:

::

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

Sets the time to wait before checking for distributed deadlocks. In particular the time to wait will be this value multiplied by PostgreSQL's `deadlock_timeout <https://www.postgresql.org/docs/current/static/runtime-config-locks.html>`_ setting. The default value is ``2``. A value of ``-1`` disables distributed deadlock detection.

Data Loading
---------------------------

citus.multi_shard_commit_protocol (enum)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the commit protocol to use when performing COPY on a hash distributed table. On each individual shard placement, the COPY is performed in a transaction block to ensure that no data is ingested if an error occurs during the COPY. However, there is a particular failure case in which the COPY succeeds on all placements, but a (hardware) failure occurs before all transactions commit. This parameter can be used to prevent data loss in that case by choosing between the following commit protocols: 

* **2pc:** (default) The transactions in which COPY is performed on the shard placements are first prepared using PostgreSQL's `two-phase commit <http://www.postgresql.org/docs/current/static/sql-prepare-transaction.html>`_ and then committed. Failed commits can be manually recovered or aborted using COMMIT PREPARED or ROLLBACK PREPARED, respectively. When using 2pc, `max_prepared_transactions <http://www.postgresql.org/docs/current/static/runtime-config-resource.html>`_ should be increased on all the workers, typically to the same value as max_connections.

* **1pc:** The transactions in which COPY is performed on the shard placements is committed in a single round. Data may be lost if a commit fails after COPY succeeds on all placements (rare).

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

citus.max_task_string_size (integer)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Sets the maximum size (in bytes) of a worker task call string. Changing this value requires a server restart, it cannot be changed at runtime.

Active worker tasks are tracked in a shared hash table on the master node. This configuration value limits the maximum size of an individual worker task, and affects the size of pre-allocated shared memory.

Minimum: 8192, Maximum 65536, Default 12288


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

* **log:** Logs statement at LOG severity level. The log line will include the SQL query that was run.

* **notice:** Logs statement at NOTICE severity level.

* **warning:** Logs statement at WARNING severity level.

* **error:** Logs statement at ERROR severity level.

Note that it may be useful to use :code:`error` during development testing, and a lower log-level like :code:`log` during actual production deployment. Choosing ``log`` will cause multi-task queries to appear in the database logs with the query itself shown after "STATEMENT."

.. code-block:: text

  LOG:  multi-task query about to be executed
  HINT:  Queries are split to multiple tasks if they have to be split into several queries on the workers.
  STATEMENT:  select * from foo;

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

.. _append_distribution:

Append Distribution
===================

.. note::

  Append distribution is a specialized technique which requires
  care to use efficiently. Hash distribution is a better choice
  for most situations.

While Citus' most common use cases involve hash data distribution,
it can also distribute timeseries data across a variable number of
shards by their order in time. This section provides a short reference
to loading, deleting, and maninpulating timeseries data.

As the name suggests, append based distribution is more suited to
append-only use cases. This typically includes event based data
which arrives in a time-ordered series. You can then distribute
your largest tables by time, and batch load your events into Citus
in intervals of N minutes. This data model can be generalized to a
number of time series use cases; for example, each line in a website's
log file, machine activity logs or aggregated website events. Append
based distribution supports more efficient range queries. This is
because given a range query on the distribution key, the Citus query
planner can easily determine which shards overlap that range and
send the query to only to relevant shards.

Hash based distribution is more suited to cases where you want to
do real-time inserts along with analytics on your data or want to
distribute by a non-ordered column (eg. user id). This data model
is relevant for real-time analytics use cases; for example, actions
in a mobile application, user website events, or social media
analytics. In this case, Citus will maintain minimum and maximum
hash ranges for all the created shards. Whenever a row is inserted,
updated or deleted, Citus will redirect the query to the correct
shard and issue it locally. This data model is more suited for doing
co-located joins and for queries involving equality based filters
on the distribution column.

Citus uses slightly different syntaxes for creation and manipulation
of append and hash distributed tables. Also, the operations supported
on the tables differ based on the distribution method chosen. In the
sections that follow, we describe the syntax for creating append
distributed tables, and also describe the operations which can be
done on them.

Creating and Distributing Tables
---------------------------------

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:

    ::

        export PATH=/usr/lib/postgresql/9.6/:$PATH


We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

To create an append distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/current/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

::

    psql -h localhost -d postgres
    CREATE TABLE github_events
    (
    	event_id bigint,
    	event_type text,
    	event_public boolean,
    	repo_id bigint,
    	payload jsonb,
    	repo jsonb,
    	actor jsonb,
    	org jsonb,
    	created_at timestamp
    );

Next, you can use the create_distributed_table() function to mark the table as an append distributed table and specify its distribution column.

::

    SELECT create_distributed_table('github_events', 'created_at', 'append');

This function informs Citus that the github_events table should be distributed by append on the created_at column. Note that this method doesn't enforce a particular distribution; it merely tells the database to keep minimum and maximum values for the created_at column in each shard which are later used by the database for optimizing queries.

Expiring Data
---------------

In append distribution, users typically want to track data only for the last few months / years. In such cases, the shards that are no longer needed still occupy disk space. To address this, Citus provides a user defined function master_apply_delete_command() to delete old shards. The function takes a `DELETE <http://www.postgresql.org/docs/current/static/sql-delete.html>`_ command as input and deletes all the shards that match the delete criteria with their metadata.

The function uses shard metadata to decide whether or not a shard needs to be deleted, so it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards are selected for deletion. The UDF then connects to the worker nodes and issues DROP commands for all the shards which need to be deleted. If a drop query for a particular shard replica fails, then that replica is marked as TO DELETE. The shard replicas which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

The example below deletes those shards from the github_events table which have all rows with created_at >= '2015-01-01 00:00:00'. Note that the table is distributed on the created_at column.

::

    SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE created_at >= ''2015-01-01 00:00:00''');
     master_apply_delete_command
    -----------------------------
                               3
    (1 row)

To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.  Please note that this function only deletes complete shards and not individual rows from shards. If your use case requires deletion of individual rows in real-time, see the section below about deleting data.

Deleting Data
---------------

The most flexible way to modify or delete rows throughout a Citus cluster with regular SQL statements:

::

  DELETE FROM github_events
  WHERE created_at >= '2015-01-01 00:03:00';

Unlike master_apply_delete_command, standard SQL works at the row- rather than shard-level to modify or delete all rows that match the condition in the where clause. It deletes rows regardless of whether they comprise an entire shard.

Dropping Tables
---------------

You can use the standard PostgreSQL `DROP TABLE <http://www.postgresql.org/docs/current/static/sql-droptable.html>`_
command to remove your append distributed tables. As with regular tables, DROP TABLE removes any
indexes, rules, triggers, and constraints that exist for the target table. In addition, it also
drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;

Data Loading
------------

Citus supports two methods to load data into your append distributed tables. The first one is suitable for bulk loads from files and involves using the \\copy command. For use cases requiring smaller, incremental data loads, Citus provides two user defined functions. We describe each of the methods and their usage below.

Bulk load using \\copy
$$$$$$$$$$$$$$$$$$$$$$$

The `\\copy <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_
command is used to copy data from a file to a distributed table while handling
replication and failures automatically. You can also use the server side `COPY command <http://www.postgresql.org/docs/current/static/sql-copy.html>`_. 
In the examples, we use the \\copy command from psql, which sends a COPY .. FROM STDIN to the server and reads files on the client side, whereas COPY from a file would read the file on the server.

You can use \\copy both on the coordinator and from any of the workers. When using it from the worker, you need to add the master_host option. Behind the scenes, \\copy first opens a connection to the coordinator using the provided master_host option and uses master_create_empty_shard to create a new shard. Then, the command connects to the workers and copies data into the replicas until the size reaches shard_max_size, at which point another new shard is created. Finally, the command fetches statistics for the shards and updates the metadata.

::

    SET citus.shard_max_size TO '64MB';
    \copy github_events from 'github_events-2015-01-01-0.csv' WITH (format CSV, master_host 'coordinator-host')

Citus assigns a unique shard id to each new shard and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. One can connect to the worker postgres instances to view or run commands on individual shards.

By default, the \\copy command depends on two configuration parameters for its behavior. These are called citus.shard_max_size and citus.shard_replication_factor.

(1) **citus.shard_max_size :-** This parameter determines the maximum size of a shard created using \\copy, and defaults to 1 GB. If the file is larger than this parameter, \\copy will break it up into multiple shards.
(2) **citus.shard_replication_factor :-** This parameter determines the number of nodes each shard gets replicated to, and defaults to one. Set it to two if you want Citus to replicate data automatically and provide fault tolerance. You may want to increase the factor even higher if you run large clusters and observe node failures on a more frequent basis.

.. note::
    The configuration setting citus.shard_replication_factor can only be set on the coordinator node.

Please note that you can load several files in parallel through separate database connections or from different nodes. It is also worth noting that \\copy always creates at least one shard and does not append to existing shards. You can use the method described below to append to previously created shards.

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Incremental loads by appending to existing shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The \\copy command always creates a new shard when it is used and is best suited for bulk loading of data. Using \\copy to load smaller data increments will result in many small shards which might not be ideal. In order to allow smaller, incremental loads into append distributed tables, Citus provides 2 user defined functions. They are master_create_empty_shard() and master_append_table_to_shard().

master_create_empty_shard() can be used to create new empty shards for a table. This function also replicates the empty shard to citus.shard_replication_factor number of nodes like the \\copy command.

master_append_table_to_shard() can be used to append the contents of a PostgreSQL table to an existing shard. This allows the user to control the shard to which the rows will be appended. It also returns the shard fill ratio which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created.

To use the above functionality, you can first insert incoming data into a regular PostgreSQL table. You can then create an empty shard using master_create_empty_shard(). Then, using master_append_table_to_shard(), you can append the contents of the staging table to the specified shard, and then subsequently delete the data from the staging table. Once the shard fill ratio returned by the append function becomes close to 1, you can create a new shard and start appending to the new one.

::

    SELECT * from master_create_empty_shard('github_events');
    master_create_empty_shard
    ---------------------------
                    102089
    (1 row)

    SELECT * from master_append_table_to_shard(102089, 'github_events_temp', 'master-101', 5432);
    master_append_table_to_shard 
    ------------------------------
            0.100548
    (1 row)

To learn more about the two UDFs, their arguments and usage, please visit the :ref:`user_defined_functions` section of the documentation.

Increasing data loading performance
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The methods described above enable you to achieve high bulk load rates which are sufficient for most use cases. If you require even higher data load rates, you can use the functions described above in several ways and write scripts to better control sharding and data loading. The next section explains how to go even faster.

Scaling Data Ingestion
----------------------

If your use-case does not require real-time ingests, then using append distributed tables will give you the highest ingest rates. This approach is more suitable for use-cases which use time-series data and where the database can be a few minutes or more behind.

Coordinator Node Bulk Ingestion (100k/s-200k/s)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

To ingest data into an append distributed table, you can use the `COPY <http://www.postgresql.org/docs/current/static/sql-copy.html>`_ command, which will create a new shard out of the data you ingest. COPY can break up files larger than the configured citus.shard_max_size into multiple shards. COPY for append distributed tables only opens connections for the new shards, which means it behaves a bit differently than COPY for hash distributed tables, which may open connections for all shards. A COPY for append distributed tables command does not ingest rows in parallel over many connections, but it is safe to run many commands in parallel.

::

    -- Set up the events table
    CREATE TABLE events (time timestamp, data jsonb);
    SELECT create_distributed_table('events', 'time', 'append');

    -- Add data into a new staging table
    \COPY events FROM 'path-to-csv-file' WITH CSV

COPY creates new shards every time it is used, which allows many files to be ingested simultaneously, but may cause issues if queries end up involving thousands of shards. An alternative way to ingest data is to append it to existing shards using the master_append_table_to_shard function. To use master_append_table_to_shard, the data needs to be loaded into a staging table and some custom logic to select an appropriate shard is required.

::

    -- Prepare a staging table
    CREATE TABLE stage_1 (LIKE events);
    \COPY stage_1 FROM 'path-to-csv-file WITH CSV

    -- In a separate transaction, append the staging table
    SELECT master_append_table_to_shard(select_events_shard(), 'stage_1', 'coordinator-host', 5432);

An example of a shard selection function is given below. It appends to a shard until its size is greater than 1GB and then creates a new one, which has the drawback of only allowing one append at a time, but the advantage of bounding shard sizes.

::

    CREATE OR REPLACE FUNCTION select_events_shard() RETURNS bigint AS $$
    DECLARE
      shard_id bigint;
    BEGIN
      SELECT shardid INTO shard_id
      FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
      WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024;

      IF shard_id IS NULL THEN
        /* no shard smaller than 1GB, create a new one */
        SELECT master_create_empty_shard('events') INTO shard_id;
      END IF;

      RETURN shard_id;
    END;
    $$ LANGUAGE plpgsql;

It may also be useful to create a sequence to generate a unique name for the staging table. This way each ingestion can be handled independently.

::

    -- Create stage table name sequence
    CREATE SEQUENCE stage_id_sequence;

    -- Generate a stage table name
    SELECT 'stage_'||nextval('stage_id_sequence');

To learn more about the master_append_table_to_shard and master_create_empty_shard UDFs, please visit the :ref:`user_defined_functions` section of the documentation.

Worker Node Bulk Ingestion (100k/s-1M/s)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

For very high data ingestion rates, data can be staged via the workers. This method scales out horizontally and provides the highest ingestion rates, but can be more complex to use. Hence, we recommend trying this method only if your data ingestion rates cannot be addressed by the previously described methods.

Append distributed tables support COPY via the worker, by specifying the address of the coordinator in a master_host option, and optionally a master_port option (defaults to 5432). COPY via the workers has the same general properties as COPY via the coordinator, except the initial parsing is not bottlenecked on the coordinator.

::

    psql -h worker-host-n -c "\COPY events FROM 'data.csv' WITH (FORMAT CSV, MASTER_HOST 'coordinator-host')"


An alternative to using COPY is to create a staging table and use standard SQL clients to append it to the distributed table, which is similar to staging data via the coordinator. An example of staging a file via a worker using psql is as follows:

::

    stage_table=$(psql -tA -h worker-host-n -c "SELECT 'stage_'||nextval('stage_id_sequence')")
    psql -h worker-host-n -c "CREATE TABLE $stage_table (time timestamp, data jsonb)"
    psql -h worker-host-n -c "\COPY $stage_table FROM 'data.csv' WITH CSV"
    psql -h coordinator-host -c "SELECT master_append_table_to_shard(choose_underutilized_shard(), '$stage_table', 'worker-host-n', 5432)"
    psql -h worker-host-n -c "DROP TABLE $stage_table"

The example above uses a choose_underutilized_shard function to select the shard to which to append. To ensure parallel data ingestion, this function should balance across many different shards.

An example choose_underutilized_shard function belows randomly picks one of the 20 smallest shards or creates a new one if there are less than 20 under 1GB. This allows 20 concurrent appends, which allows data ingestion of up to 1 million rows/s (depending on indexes, size, capacity).

::

    /* Choose a shard to which to append */
    CREATE OR REPLACE FUNCTION choose_underutilized_shard()
    RETURNS bigint LANGUAGE plpgsql
    AS $function$
    DECLARE
      shard_id bigint;
      num_small_shards int;
    BEGIN
      SELECT shardid, count(*) OVER () INTO shard_id, num_small_shards
      FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
      WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024
      GROUP BY shardid ORDER BY RANDOM() ASC;

      IF num_small_shards IS NULL OR num_small_shards < 20 THEN
        SELECT master_create_empty_shard('events') INTO shard_id;
      END IF;

      RETURN shard_id;
    END;
    $function$;
    
A drawback of ingesting into many shards concurrently is that shards may span longer time ranges, which means that queries for a specific time period may involve shards that contain a lot of data outside of that period.

In addition to copying into temporary staging tables, it is also possible to set up tables on the workers which can continuously take INSERTs. In that case, the data has to be periodically moved into a staging table and then appended, but this requires more advanced scripting.

Pre-processing Data in Citus
$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The format in which raw data is delivered often differs from the schema used in the database. For example, the raw data may be in the form of log files in which every line is a JSON object, while in the database table it is more efficient to store common values in separate columns. Moreover, a distributed table should always have a distribution column. Fortunately, PostgreSQL is a very powerful data processing tool. You can apply arbitrary pre-processing using SQL before putting the results into a staging table.

For example, assume we have the following table schema and want to load the compressed JSON logs from `githubarchive.org <http://www.githubarchive.org>`_:

::

    CREATE TABLE github_events
    (
        event_id bigint,
        event_type text,
        event_public boolean,
        repo_id bigint,
        payload jsonb,
        repo jsonb,
        actor jsonb,
        org jsonb,
        created_at timestamp
    );
    SELECT create_distributed_table('github_events', 'created_at', 'append');


To load the data, we can download the data, decompress it, filter out unsupported rows, and extract the fields in which we are interested into a staging table using 3 commands:

::

    CREATE TEMPORARY TABLE prepare_1 (data jsonb);

    -- Load a file directly from Github archive and filter out rows with unescaped 0-bytes
    COPY prepare_1 FROM PROGRAM
    'curl -s http://data.githubarchive.org/2016-01-01-15.json.gz | zcat | grep -v "\\u0000"'
    CSV QUOTE e'\x01' DELIMITER e'\x02';

    -- Prepare a staging table
    CREATE TABLE stage_1 AS
    SELECT (data->>'id')::bigint event_id,
           (data->>'type') event_type,
           (data->>'public')::boolean event_public,
           (data->'repo'->>'id')::bigint repo_id,
           (data->'payload') payload,
           (data->'actor') actor,
           (data->'org') org,
           (data->>'created_at')::timestamp created_at FROM prepare_1;

You can then use the master_append_table_to_shard function to append this staging table to the distributed table.

This approach works especially well when staging data via the workers, since the pre-processing itself can be scaled out by running it on many workers in parallel for different chunks of input data.

For a more complete example, see `Interactive Analytics on GitHub Data using PostgreSQL with Citus <https://www.citusdata.com/blog/14-marco/402-interactive-analytics-github-data-using-postgresql-citus>`_.
