.. _metadata_tables:

Metadata Tables Reference
##########################

Citus divides each distributed table into multiple logical shards based on the distribution column. The master then maintains metadata tables to track statistics and information about the health and location of these shards. In this section, we describe each of these metadata tables and their schema. You can view and query these tables using SQL after logging into the master node.

Partition table
-----------------

The pg_dist_partition table stores metadata about which tables in the database are distributed. For each distributed table, it also stores information about the distribution method and detailed information about the distribution column.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| logicalrelid   |           oid        | | Distributed table to which this row corresponds. This value references  | 
|                |                      | | the relfilenode column in the pg_class system catalog table.            |
+----------------+----------------------+---------------------------------------------------------------------------+   
|  partmethod    |            char      | | The method used for partitioning / distribution. The values of this     |
|                |                      | | column corresponding to different distribution methods are :-           |
|                |                      | | append: 'a'                                                             |
|                |                      | | hash: 'h'                                                               |
+----------------+----------------------+---------------------------------------------------------------------------+
|   partkey      |            text      | | Detailed information about the distribution column including column     |
|                |                      | | number, type and other relevant information.                            |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_partition;
     logicalrelid | partmethod |                                                     	partkey                                                    	 
    --------------+------------+-------------------------------------------------------------------------------------------------------------------------
           488843 |     r      | {VAR :varno 1 :varattno 4 :vartype 20 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnoold 1 :varoattno 4 :location 232}

    (1 row)


Shard table
-----------------

The pg_dist_shard table stores metadata about individual shards of a table. This includes information about which distributed table the shard belongs to and statistics about the distribution column for that shard. For append distributed tables, these statistics correspond to min / max values of the distribution column. In case of hash distributed tables, they are hash token ranges assigned to that shard. These statistics are used for pruning away unrelated shards during SELECT queries.

+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| logicalrelid   |           oid        | | Distributed table to which this shard belongs. This value references the|
|                |                      | | relfilenode column in the pg_class system catalog table.                |
+----------------+----------------------+---------------------------------------------------------------------------+
|    shardid     |         bigint       | | Globally unique identifier assigned to this shard.                      |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardstorage   |            char      | | Type of storage used for this shard. Different storage types are        |
|                |                      | | discussed in the table below.                                           |
+----------------+----------------------+---------------------------------------------------------------------------+
|  shardalias    |            text      | | Deprecated and unused column. Will be removed in a future release.      |
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
     logicalrelid | shardid | shardstorage | shardalias | shardminvalue | shardmaxvalue
    --------------+---------+--------------+------------+---------------+---------------
           488843 |  102065 | t        	   |        	| 27        	| 14995004
           488843 |  102066 | t        	   |        	| 15001035  	| 25269705
           488843 |  102067 | t            |        	| 25273785  	| 28570113
           488843 |  102068 | t        	   |        	| 28570150  	| 28678869

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



Shard placement table
---------------------------------------

The pg_dist_shard_placement table tracks the location of shard replicas on worker nodes. Each replica of a shard assigned to a specific node is called a shard placement. This table stores information about the health and location of each shard placement.


+----------------+----------------------+---------------------------------------------------------------------------+
|      Name      |         Type         |       Description                                                         |
+================+======================+===========================================================================+
| shardid   	 |      bigint          | | Shard identifier associated with this placement. This values references |
|                |                      | | the shardid column in the pg_dist_shard catalog table.                  |
+----------------+----------------------+---------------------------------------------------------------------------+ 
| shardstate     |        int       	| | Describes the state of this placement. Different shard states are       |
|                |                      | | discussed in the section below.                                         |
+----------------+----------------------+---------------------------------------------------------------------------+
| shardlength    |          bigint      | | For append distributed tables, the size of the shard placement on the   |
|                |                      | | worker node in bytes.                                                   |
|                |                      | | For hash distributed tables, zero.                                      |
+----------------+----------------------+---------------------------------------------------------------------------+
|  nodename      |            text      | | DNS host name of the worker node PostgreSQL server hosting this shard   |
|                |                      | | placement.                                                              |
+----------------+----------------------+---------------------------------------------------------------------------+
| nodeport       |            int       | | Port number on which the worker node PostgreSQL server hosting this     |
|                |                      | | shard placement is listening.                                           |
+----------------+----------------------+---------------------------------------------------------------------------+

::

    SELECT * from pg_dist_shard_placement;
     shardid | shardstate | shardlength | nodename  | nodeport
    ---------+------------+-------------+-----------+----------
      102065 |      	1 | 	7307264 | localhost | 	9701
      102065 |      	1 | 	7307264 | localhost | 	9700
      102066 |      	1 | 	5890048 | localhost | 	9700
      102066 |      	1 | 	5890048 | localhost | 	9701
      102067 |      	1 | 	5242880 | localhost | 	9701
      102067 |      	1 | 	5242880 | localhost | 	9700
      102068 |      	1 | 	3923968 | localhost | 	9700
      102068 |      	1 | 	3923968 | localhost | 	9701

    (8 rows)

Shard Placement States
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus manages shard health on a per-placement basis and automatically marks a placement as unavailable if leaving the placement in service would put the cluster in an inconsistent state. The shardstate column in the pg_dist_shard_placement table is used to store the state of shard placements. A brief overview of different shard placement states and their representation is below.


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

