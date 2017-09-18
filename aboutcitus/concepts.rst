.. _citus_concepts:

Concepts
========

This section is a brief glossary of common terms in our documentation, with links to more complete information.

.. _define_node:

Node
----

In Citus terminology, a *node* is an independent computer running its own instance of PostgreSQL. Nodes collaborate in a *cluster* to compute query results, and each node holds a part of the total data in the database. Every cluster has one special node called the *coordinator.* Applications send their queries to the coordinator node which relays it to the relevant workers and accumulates the results.

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
