.. _user_defined_functions:

User Defined Functions Reference
#################################

This section contains reference information for the User Defined Functions provided by Citus. These functions help in providing additional distributed functionality to Citus other than the standard SQL commands.

Table and Shard DDL
-------------------

master_create_distributed_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_create_distributed_table() function is used to define a distributed table. This function takes in a table name, the distribution column and distribution method and inserts appropriate metadata to mark the table as distributed.

Arguments
************************

**table_name:** Name of the table which needs to be distributed.

**distribution_column:** The column on which the table is to be distributed.

**distribution_method:** The method according to which the table is to be distributed. Permissible values are append, hash or range.

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

The master_create_worker_shards() function creates a specified number of worker shards with the desired replication factor for a *hash* distributed table. While doing so, the function also assigns a portion of the hash token space (which spans between -2 Billion and 2 Billion) to each shard. Once all shards are created, this function saves all distributed metadata on the master.

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

The master_create_empty_shard() function can be used to create an empty shard for an *append* distributed table. Behind the covers, the function first selects shard_replication_factor workers to create the shard on. Then, it connects to the workers and creates empty placements for the shard on the selected workers. Finally, the metadata is updated for these placements on the master to make these shards visible to future queries. The function errors out if it is unable to create the desired number of shard placements.

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

Behind the covers, this function connects to all the worker nodes which have shards matching the delete criteria and sends them a command to drop the selected shards. Then, the function updates the corresponding metadata on the master. If the function is able to successfully delete a shard placement, then the metadata for it is deleted. If a particular placement could not be deleted, then it is marked as TO DELETE. The placements which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

Arguments
*********************

**delete_command:** valid `SQL DELETE <http://www.postgresql.org/docs/9.5/static/sql-delete.html>`_ command

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

Metadata / Configuration Information
------------------------------------------------------------------------

master_get_active_worker_nodes
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_get_active_worker_nodes() function returns a list of active worker host names and port numbers. Currently, the function assumes that all the worker nodes in pg_worker_list.conf are active.

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

**part_method:** Distribution method used for the table. May be 'a' (append), 'h' (hash) or 'r' (range).

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

.. _cluster_management_functions:

Cluster Management And Repair Functions
----------------------------------------

master_copy_shard_placement
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

If a shard placement fails to be updated during a modification command or a DDL operation, then it gets marked as inactive. The master_copy_shard_placement function can then be called to repair an inactive shard placement using data from a healthy placement.

To repair a shard, the function first drops the unhealthy shard placement and recreates it using the schema on the master. Once the shard placement is created, the function copies data from the healthy placement and updates the metadata to mark the new shard placement as healthy. This function ensures that the shard will be protected from any concurrent modifications during the repair.

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


rebalance_table_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Note: The rebalance_table_shards function is a part of Citus Enterprise. Please contact engage@citusdata.com to obtain this functionality.

The rebalance_table_shards() function moves shards of the given table to make them evenly distributed among the workers. The function first calculates the list of moves it needs to make in order to ensure that the cluster is balanced within the given threshold. Then, it moves shard placements one by one from the source node to the destination node and updates the corresponding shard metadata to reflect the move.

Arguments
**************************

**table_name:** The name of the table whose shards need to be rebalanced.

**threshold:** (Optional) A float number between 0.0 and 1.0 which indicates the maximum difference ratio of node utilization from average utilization. For example, specifying 0.1 will cause the shard rebalancer to attempt to balance all nodes to hold the same number of shards ±10%. Specifically, the shard rebalancer will try to converge utilization of all worker nodes to the (1 - threshold) * average_utilization ... (1 + threshold) * average_utilization range.

**max_shard_moves:** (Optional) The maximum number of shards to move.

**excluded_shard_list:** (Optional) Identifiers of shards which shouldn't be moved during the rebalance operation.

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

Note: The replicate_table_shards function is a part of Citus Enterprise. Please contact engage@citusdata.com to obtain this functionality.

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
