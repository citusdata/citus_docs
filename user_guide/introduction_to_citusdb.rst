.. _introduction_to_citusdb:

Introduction To CitusDB
#######################

What is CitusDB?
-------------------------

CitusDB is a distributed database that is optimized for real-time big data workloads. CitusDB scales out PostgreSQL across a cluster of physical or virtual servers through sharding and replication. The advanced CitusDB query engine then parallelizes incoming SQL queries across these servers to enable real-time responses. CitusDB also intelligently recovers from mid-query failures by automatically failing over to other replicas, allowing users to maintain high availability.

CitusDB is not a fork of PostgreSQL but rather extends it by using the hook and extension APIs. As a result, CitusDB can be used as a drop in replacement for PostgreSQL without making any changes at the application layer. CitusDB is rebased on all major PostgreSQL releases, allowing users to benefit from new PostgreSQL features and maintain compatibility with existing PostgreSQL tools.

Architecture
-------------------
At a high level, CitusDB distributes the data across a cluster of commodity servers.
Incoming SQL queries are then parallel processed across the servers.

.. image:: ../images/citusdb-basic-arch.png

In the sections below, we briefly explain the concepts relating to CitusDB’s architecture.

Master / Worker Nodes
$$$$$$$$$$$$$$$$$$$$$$$$$

The user chooses one of the nodes in the cluster as the master node. He then adds the names of worker nodes to a membership file on the master node. From that point on, the user interacts with the master node through standard PostgreSQL interfaces for data loading and querying. All the data is distributed across the worker nodes. The master node only stores metadata about the shards.

Logical Sharding
$$$$$$$$$$$$$$$$$$$$$$$

CitusDB utilizes a modular block architecture which is similar to Hadoop Distributed File System blocks but uses PostgreSQL tables on the worker nodes instead of files. Each of these tables is a horizontal partition or a logical “shard”. The CitusDB master node then maintains metadata tables which track all the cluster nodes and the locations of the shards on those nodes.

Each shard is replicated on at least two of the cluster nodes (Users can configure this to a higher value). As a result, the loss of a single node does not impact data availability. The CitusDB logical sharding architecture also allows new nodes to be added at any time to increase the capacity and processing power of the cluster.


Metadata Tables
$$$$$$$$$$$$$$$$$

The CitusDB master node maintains metadata tables to track all of the cluster nodes and the locations of the database shards on those nodes. These tables also maintain statistics like size and min/max values about the shards which help CitusDB’s distributed query planner to optimize the incoming queries. The metadata tables are small (typically a few MBs in size) and can be replicated and quickly restored if the node ever experiences a failure.

You can view the metadata by running the following queries on the master node.

::

    SELECT * from pg_dist_partition;
     logicalrelid | partmethod |                                                     	partkey                                                    	 
    --------------+------------+-------------------------------------------------------------------------------------------------------------------------
           488843 | r          | {VAR :varno 1 :varattno 4 :vartype 20 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnoold 1 :varoattno 4 :location 232}
    (1 row)

    SELECT * from pg_dist_shard;
     logicalrelid | shardid | shardstorage | shardalias | shardminvalue | shardmaxvalue
    --------------+---------+--------------+------------+---------------+---------------
           488843 |  102065 | t        	   |        	| 27        	| 14995004
           488843 |  102066 | t            |        	| 15001035  	| 25269705
           488843 |  102067 | t            |        	| 25273785  	| 28570113
           488843 |  102068 | t            |        	| 28570150  	| 28678869
    (4 rows)

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

To learn more about the metadata tables and their schema, please visit the :ref:`reference_index` section of our documentation.

Query processing
$$$$$$$$$$$$$$$$$$$$$$$$$$$$

When the user issues a query, the master node partitions the query into smaller query fragments where each query fragment can be run independently on a shard. This allows CitusDB to distribute each query across the cluster nodes, utilizing the processing power of all of the involved nodes and also of individual cores on each node. The master node then assigns the query fragments to worker nodes, oversees their execution, merges their results, and returns the final result to the user. To ensure that all queries are executed in a scalable manner, the master node also applies optimizations that minimize the amount of data transferred across the network.

Failure Handling
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

CitusDB can easily tolerate worker node failures because of its logical sharding-based architecture. If a node fails mid-query, CitusDB completes the query by re-routing the failed portions of the query to other nodes which have a copy of the shard. If the worker node is permanently down, users can easily rebalance / move the shards from different nodes onto other nodes to maintain the same level of availability.

