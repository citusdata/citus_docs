.. _user_defined_functions:

Citus Utility Functions
=======================

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

**distribution_type:** (Optional) The method according to which the table is
to be distributed. Permissible values are append or hash, and defaults to 'hash'.

**colocate_with:** (Optional) include current table in the co-location group of another table. By default tables are co-located when they are distributed by columns of the same type, have the same shard count, and have the same replication factor. Possible values for :code:`colocate_with` are :code:`default`, :code:`none` to start a new co-location group, or the name of another table to co-locate with that table.  (See :ref:`colocation_groups`.)

Keep in mind that the default value of ``colocate_with`` does implicit co-location. As :ref:`colocation` explains, this can be a great thing when tables are related or will be joined. However when two tables are unrelated but happen to use the same datatype for their distribution columns, accidentally co-locating them can decrease performance during :ref:`shard rebalancing <shard_rebalancing>`. The table shards will be moved together unnecessarily in a "cascade."

If a new distributed table is not related to other tables, it's best to specify ``colocate_with => 'none'``.

Return Value
********************************

N/A

Example
*************************

This example informs the database that the github_events table should be distributed by hash on the repo_id column.

.. code-block:: postgresql

  SELECT create_distributed_table('github_events', 'repo_id');

  -- alternatively, to be more explicit:
  SELECT create_distributed_table('github_events', 'repo_id',
                                  colocate_with => 'github_repo');

For more examples, see :ref:`ddl`.

.. _create_reference_table:

create_reference_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The create_reference_table() function is used to define a small reference or
dimension table. This function takes in a table name, and creates a distributed
table with just one shard, replicated to every worker node.

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

.. code-block:: postgresql

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

.. code-block:: postgresql

	SELECT upgrade_to_reference_table('nation');

.. _mark_tables_colocated:

mark_tables_colocated
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The mark_tables_colocated() function takes a distributed table (the source), and a list of others (the targets), and puts the targets into the same co-location group as the source. If the source is not yet in a group, this function creates one, and assigns the source and targets to it.

Usually colocating tables ought to be done at table distribution time via the ``colocate_with`` parameter of :ref:`create_distributed_table`. But ``mark_tables_colocated`` can take care of it if necessary.

Arguments
************************

**source_table_name:** Name of the distributed table whose co-location group the targets will be assigned to match.

**target_table_names:** Array of names of the distributed target tables, must be non-empty. These distributed tables must match the source table in:

  * distribution method
  * distribution column type
  * replication type
  * shard count

Failing this, Citus will raise an error. For instance, attempting to colocate tables ``apples`` and ``oranges`` whose distribution column types differ results in:

::

  ERROR:  XX000: cannot colocate tables apples and oranges
  DETAIL:  Distribution column types don't match for apples and oranges.

Return Value
********************************

N/A

Example
*************************

This example puts ``products`` and ``line_items`` in the same co-location group as ``stores``. The example assumes that these tables are all distributed on a column with matching type, most likely a "store id."

.. code-block:: postgresql

  SELECT mark_tables_colocated('stores', ARRAY['products', 'line_items']);

.. _create_distributed_function:

create_distributed_function
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Propagates a function from the coordinator node to workers, and marks it for
distributed execution. When a distributed function is called on the
coordinator, Citus uses the value of the "distribution argument" to pick a
worker node to run the function. Executing the function on workers increases
parallelism, and can bring the code closer to data in shards for lower latency.

Note that the Postgres search path is not propagated from the coordinator to
workers during distributed function execution, so distributed function code
should fully-qualify the names of database objects. Also notices emitted by
the functions will not be displayed to the user.

Arguments
************************

**function_name:** Name of the function to be distributed. The name must
include the function's parameter types in parentheses, because multiple
functions can have the same name in PostgreSQL. For instance, ``'foo(int)'`` is
different from ``'foo(int, text)'``.

**distribution_arg_name:** (Optional) The argument name by which to distribute.
For convenience (or if the function arguments do not have names), a positional
placeholder is allowed, such as ``'$1'``. If this parameter is not specified,
then the function named by ``function_name`` is merely created on the workers.
If worker nodes are added in the future the function will automatically be
created there too.

**colocate_with:** (Optional) When the distributed function reads or writes to
a distributed table (or more generally :ref:`colocation_groups`), be sure to
name that table using the ``colocate_with`` parameter. This ensures that each
invocation of the function runs on the worker node containing relevant shards.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  -- an example function which updates a hypothetical
  -- event_responses table which itself is distributed by event_id
  CREATE OR REPLACE FUNCTION
    register_for_event(p_event_id int, p_user_id int)
  RETURNS void LANGUAGE plpgsql AS $fn$
  BEGIN
    INSERT INTO event_responses VALUES ($1, $2, 'yes')
    ON CONFLICT (event_id, user_id)
    DO UPDATE SET response = EXCLUDED.response;
  END;
  $fn$;

  -- distribute the function to workers, using the p_event_id argument
  -- to determine which shard each invocation affects, and explicitly
  -- colocating with event_responses which the function updates
  SELECT create_distributed_function(
    'register_for_event(int, int)', 'p_event_id',
    colocate_with := 'event_responses'
  );

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

    SELECT * from master_append_table_to_shard(102089,'github_events_local','master-101', 5432);
     master_append_table_to_shard
    ------------------------------
                     0.100548
    (1 row)


master_apply_delete_command
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_apply_delete_command() function is used to delete shards which match the criteria specified by the delete command on an *append* distributed table. This function deletes a shard only if all rows in the shard match the delete criteria. As the function uses shard metadata to decide whether or not a shard needs to be deleted, it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards of that table are deleted.

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

    select master_remove_node('new-node', 12345);
     master_remove_node 
    --------------------
     
    (1 row)

master_get_active_worker_nodes
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_get_active_worker_nodes() function returns a list of active worker
host names and port numbers.

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

.. code-block:: postgresql

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

.. code-block:: postgresql

    SELECT * from master_get_table_metadata('github_events');
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

.. code-block:: postgresql

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


citus_stat_statements_reset
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Removes all rows from :ref:`citus_stat_statements <citus_stat_statements>`. Note that this works independently from ``pg_stat_statements_reset()``. To reset all stats, call both functions.

Arguments
*********

N/A

Return Value
************

None

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

.. code-block:: postgresql

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

.. code-block:: postgresql

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

.. code-block:: postgresql

	SELECT rebalance_table_shards('github_events');

This example usage will attempt to rebalance the github_events table without moving shards with id 1 and 2.

.. code-block:: postgresql

	SELECT rebalance_table_shards('github_events', excluded_shard_list:='{1,2}');

.. _get_rebalance_progress:

get_rebalance_progress
$$$$$$$$$$$$$$$$$$$$$$

.. note::

  The get_rebalance_progress() function is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

Once a shard rebalance begins, the ``get_rebalance_progress()`` function lists the progress of every shard involved. It monitors the moves planned and executed by ``rebalance_table_shards()``.

Arguments
**************************

N/A

Return Value
*********************************

Tuples containing these columns:

* **sessionid**: Postgres PID of the rebalance monitor
* **table_name**: The table whose shards are moving
* **shardid**: The shard in question
* **shard_size**: Size in bytes
* **sourcename**: Hostname of the source node
* **sourceport**: Port of the source node
* **targetname**: Hostname of the destination node
* **targetport**: Port of the destination node
* **progress**: 0 = waiting to be moved; 1 = moving; 2 = complete

Example
**************************

.. code-block:: sql

  SELECT * FROM get_rebalance_progress();

::

  ┌───────────┬────────────┬─────────┬────────────┬───────────────┬────────────┬───────────────┬────────────┬──────────┐
  │ sessionid │ table_name │ shardid │ shard_size │  sourcename   │ sourceport │  targetname   │ targetport │ progress │
  ├───────────┼────────────┼─────────┼────────────┼───────────────┼────────────┼───────────────┼────────────┼──────────┤
  │      7083 │ foo        │  102008 │    1204224 │ n1.foobar.com │       5432 │ n4.foobar.com │       5432 │        0 │
  │      7083 │ foo        │  102009 │    1802240 │ n1.foobar.com │       5432 │ n4.foobar.com │       5432 │        0 │
  │      7083 │ foo        │  102018 │     614400 │ n2.foobar.com │       5432 │ n4.foobar.com │       5432 │        1 │
  │      7083 │ foo        │  102019 │       8192 │ n3.foobar.com │       5432 │ n4.foobar.com │       5432 │        2 │
  └───────────┴────────────┴─────────┴────────────┴───────────────┴────────────┴───────────────┴────────────┴──────────┘

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

.. code-block:: postgresql

	SELECT replicate_table_shards('github_events');

This example will attempt to bring the shards of the github_events table to the desired replication factor with a maximum of 10 shard copies. This means that the rebalancer will copy only a maximum of 10 shards in its attempt to reach the desired replication factor.

.. code-block:: postgresql

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

citus_create_restore_point
$$$$$$$$$$$$$$$$$$$$$$$$$$

Temporarily blocks writes to the cluster, and creates a named restore point on all nodes. This function is similar to `pg_create_restore_point <https://www.postgresql.org/docs/10/static/functions-admin.html#FUNCTIONS-ADMIN-BACKUP>`_, but applies to all nodes and makes sure the restore point is consistent across them. This function is well suited to doing point-in-time recovery, and cluster forking.

Arguments
*************************

**name:** The name of the restore point to create.

Return Value
***************************

**coordinator_lsn:** Log sequence number of the restore point in the coordinator node WAL.

Examples
**************************

.. code-block:: postgresql

  select citus_create_restore_point('foo');

::

  ┌────────────────────────────┐
  │ citus_create_restore_point │
  ├────────────────────────────┤
  │ 0/1EA2808                  │
  └────────────────────────────┘
