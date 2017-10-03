.. _citus_concepts:


Concepts
========

This section is a brief glossary of common terms in our documentation, with links to more complete information.

Distributed Architecture
------------------------

Citus is a PostgreSQL `extension <https://www.postgresql.org/docs/9.6/static/external-extensions.html>`_ that allows commodity database servers (called *nodes*) to coordinate with one another in a "shared nothing" architecture. The nodes form a *cluster* that allows PostgreSQL to hold more data and use more CPU cores than would be possible on a single computer. This architecture also allows the database to scale simply by adding more nodes into the cluster.

[Find updated picture of architecture]

Every cluster has one special node called the *coordinator.* Applications send their queries to the coordinator node which relays it to the relevant workers and accumulates the results. Each query is either *routed* or *parallelized,* depending on whether the required data lives on a single node or multiple.

.. The existing section: https://docs.citusdata.com/en/v7.0/aboutcitus/introduction_to_citus.html is out of date. I think we should get rid of it, and fold pieces of it into this Concepts section. I’m thinking of something like:
.. Shared nothing, scale out.
.. Data is partitioned, queries are either routed/parallelized.
.. Is an extension of PostgreSQL (not a fork)
.. What are the cluster components (see: https://docs.memsql.com/concepts/v5.8/distributed-architecture/)
.. Coordinator (What does it contain? What does it do?)
.. Worker (See above)
.. (Maybe we also provide an updated diagram? Could scour through Citus presentations to see if there is something new).

At a high level, Citus distributes the data across a cluster of commodity servers.  Incoming SQL queries are then parallel processed across these servers.

.. image:: ../images/citus-basic-arch.png

In the sections below, we briefly explain the concepts relating to Citus’s architecture.

Coordinator / Worker Nodes
$$$$$$$$$$$$$$$$$$$$$$$$$$

You first choose one of the PostgreSQL instances in the cluster as the Citus coordinator. You then add the DNS names of worker PostgreSQL instances (Citus workers) to a metadata table on the coordinator. From that point on, you interact with the coordinator through standard PostgreSQL interfaces for data loading and querying. All the data is distributed across the workers.  The coordinator only stores metadata about the shards.

Logical Sharding
$$$$$$$$$$$$$$$$$$$$$$$

Citus utilizes a modular block architecture which is similar to Hadoop Distributed File System blocks but uses PostgreSQL tables on the workers instead of files. Each of these tables is a horizontal partition or a logical “shard”. The Citus coordinator then maintains metadata tables which track all the workers and the locations of the shards on the workers.

Each shard is replicated on at least two of the workers (Users can configure this to a higher value). As a result, the loss of a single machine does not impact data availability. The Citus logical sharding architecture also allows new workers to be added at any time to increase the capacity and processing power of the cluster.

Metadata Tables
$$$$$$$$$$$$$$$$$

The Citus coordinator maintains metadata tables to track all the workers and the locations of the database shards on them. These tables also maintain statistics like size and min/max values about the shards which help Citus’s distributed query planner to optimize the incoming queries. The metadata tables are small (typically a few MBs in size) and can be replicated and quickly restored if the coordinator ever experiences a failure.

To learn more about the metadata tables and their schema, please visit the :ref:`metadata_tables` section of our documentation.

Query Processing
$$$$$$$$$$$$$$$$

When the user issues a query, the Citus coordinator partitions it into smaller query fragments where each query fragment can be run independently on a worker shard. This allows Citus to distribute each query across the cluster, utilizing the processing power of all of the involved nodes and also of individual cores on each node. The coordinator then assigns the query fragments to workers, oversees their execution, merges their results, and returns the final result to the user. To ensure that all queries are executed in a scalable manner, the coordinator also applies optimizations that minimize the amount of data transferred across the network.

Failure Handling
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus can easily tolerate worker failures because of its logical sharding-based architecture. If a worker fails mid-query, Citus completes the query by re-routing the failed portions of the query to other workers which have a copy of the shard. If a worker is permanently down, users can easily rebalance the shards onto other workers to maintain the same level of availability.

.. _define_node:

Node
----


Citus also supports an :ref:`mx` mode to allow queries directly against workers. An MX cluster still has a coordinator node, but clients use the coordinator only for :ref:`ddl`.

.. _define_shard:

Shards and Partitioning
-----------------------

Citus horizontally *partitions* distributed tables, meaning it splits the table into logical pieces, storing different rows on different nodes. A *shard* is a bundle of rows for a certain table stored on a certain node. A node may hold more than one shard per table.

Citus uses algorithmic sharding to assign rows to shards. This means the assignment is made deterministically based on a value in each row rather than by consulting an external service. Every shard has a "hash range" which is a range of numbers disjoint from those of the other shards. For each table row, Citus hashes the value in a designated column, and assigns the row to that shard whose hash range contains the hashed value.

Placement
---------

We've already seen the assignment of rows to shards. There's another assignment: shards to nodes. This is called *shard placement.* The latter is not algorithmic, but dynamic. Citus tracks shard placements in a metadata table on the coordinator node. This allows shards to be moved between nodes as desired. To learn more, see :ref:`placements`.

Citus can optionally store extra copies of shards for safe keeping, and those replicas have placements as well.

Co-Location
-----------

Since shards and their replicas can be placed on nodes as desired, it makes sense to place shards containing related rows of related tables together on the same nodes. That way join queries between them can avoid sending as much information over the network, and can be performed inside a single Citus node.

For a full explanation and examples of this concept, see :ref:`colocation`.

Query Routing
-------------

When an application sends a query to the coordinator node of a cluster, that node examines the query. It looks at the query structure, including the WHERE clause, to determine which shards hold the required information.

When these shards are placed on multiple nodes, the coordinator opens one PostgreSQL connection per-shard to the workers and executes a *fragment query* on each connection. A fragment query is a modification of the original query that requests just the data stored in that shard (for instance it may have a stricter filter in the WHERE clause). The coordinator fetches the results from each fragment, merges them, and gives the final results back to the application.

Alternately, when all shards needed for the query are placed on the same worker node, the coordinator *pushes down*, or *routes* the query unmodified to that worker. The coordinator also passes the results back to the application unmodified. Router execution is typical for multi-tenant SaaS applications on Citus.

Parallelism
-----------

Spreading queries across multiple machines allows more queries to run at once, and allows processing speed to scale by adding new machines to the cluster. Additionally splitting a single query into fragments as described in the previous section boosts the processing power devoted to it. The latter situation achieves the greatest *parallelism,* meaning utilization of CPU cores.

Queries reading or affecting shards spread evenly across many nodes are able to run at "real-time" speed. Note that the results of the query still need to pass back through the coordinator node, so the speedup is most apparent when the final results are compact, such as aggregate functions like counting and descriptive statistics.

Table Types
-----------

Citus treats every table in one of three ways, depending on configuration by the cluster administrator.

1. **Local tables.** These are ordinary tables on the coordinator node. Queries that consult them will not propagate to workers. Examples of these include temp tables and Citus metadata tables.
2. **Distributed tables.** The most common case, where the table is broken into shards distributed across the workers. Queries on distributed tables are processed as described above in Query Routing.
3. **Reference tables.** These are a special kind of a distributed table. Their entire contents are concentrated into a single shard which is replicated on every worker. A reference table can thus be joined with any other distributed table without network overhead.




.. Table Types:
.. Distributed tables 
.. Normal use-case
.. Hash-partitioned into smaller shards.
.. Partitioned using one of the table columns.
.. Reference Tables
.. Shared data across nodes
.. Local tables
.. Tables on the master only. Not partitioned/distributed.

.. (Also provide links to DML section, possibly example create-table statements…)

.. Partition Column:
.. (I am not sure if it should be above, but maybe it needs its own section)
.. Citus computes a hash of the values of this column, and routes them to different nodes.
.. Important because of performance/functionality reasons.
.. See links to “choosing a partition column”
.. Shard/Partition:

.. Contains a subset of the hash-values of the partition column.
.. Show how hash-space is divided amongst shards.
.. Links to Production sizing for choosing shard-count.
.. Show example output of pg_dist_shard.
.. On worker node, is just a regular PostgreSQL table.
.. Talk about shard_id, and worker table is just <tablename>_<shardid>.
.. (Not all above needs to be covered, just putting in some thoughts)

.. Placement:
.. Represents physical location of above Shard.
.. Shows hostname where it lives.
.. If you use Citus replication, we can have multiple of these per shard.
.. Usually with streaming replication, only one placement per shard.
.. Show query to see where these live.
.. (It’s also an option to omit this section entirely. We can chat with @Samay/Sai on this)

.. Co-location:
.. (The explanation you have in PR makes sense, could you also provide an example of what we mean by ‘related’ rows? E.g. sharding by say user-id, so all data for a user is on on node).

.. Query Processing:
.. (I think existing content in your PR is good for planning. I don’t think we need something separate for execution).

