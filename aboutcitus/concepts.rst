.. _citus_concepts:


Concepts
========

This section is a brief introduction to common terms in our documentation, with links to more complete information.

Distributed Architecture
------------------------

Citus is a PostgreSQL `extension <https://www.postgresql.org/docs/9.6/static/external-extensions.html>`_ that allows commodity database servers (called *nodes*) to coordinate with one another in a "shared nothing" architecture. The nodes form a *cluster* that allows PostgreSQL to hold more data and use more CPU cores than would be possible on a single computer. This architecture also allows the database to scale by simply adding more nodes to the cluster.

Nodes: Coordinator and Workers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Every cluster has one special node called the *coordinator* (the others are known as workers). Applications send their queries to the coordinator node which relays it to the relevant workers and accumulates the results.

For each query, the coordinator either *routes* it to a single worker node, or *parallelizes* it across several depending on whether the required data lives on a single node or multiple.  The coordinator knows how to do this by consulting its metadata tables. These Citus-specific tables track the DNS names and health of worker nodes, and the distribution of data across nodes. For more information, see our :ref:`metadata_tables`.

[picture of routed vs parallelized]

Citus also supports an :ref:`mx` mode to allow queries directly against workers. An MX cluster still has a coordinator node, but clients use the coordinator only for :ref:`ddl`.

Table Types
-----------

There are three types of tables in a Citus cluster, each used for different purposes.

Type 1: Distributed Tables
~~~~~~~~~~~~~~~~~~~~~~~~~~

The first type, and most common, is *distributed* tables. These appear to be normal tables to SQL statements, but are stored internally as many smaller physical tables across worker nodes.

[image of a table sliced horizontally, with slices placed on workers]

Citus horizontally *partitions* distributed tables, meaning it splits the table into logical pieces, storing different rows in smaller tables on workers. These smaller tables are called *shards*. Note that one node may hold more than one shard per distributed table.

Distribution Column
!!!!!!!!!!!!!!!!!!!

Citus uses algorithmic sharding to assign rows to shards. This means the assignment is made deterministically -- in our case based on the value of a particular column called the *distribution column.* The cluster administrator must designate this column when distributing a table. Making the right choice is important for performance and functionality, as described in the general topic of :ref:`Distributed Data Modeling <distributed_data_modeling>`.

Type 2: Reference Tables
~~~~~~~~~~~~~~~~~~~~~~~~

The next type of table in Citus is the *reference* table, which is a species of distributed table. Its entire contents are concentrated into a single shard which is replicated on every worker. Thus any query on any worker can access the reference information locally, without the network overhead of requesting rows from another node. Reference tables have no distribution column because there is no need to distinguish separate shards per row.

Citus runs not only SQL but DDL statements throughout a cluster, so changing the schema of a distributed table cascades to update all the table's shards across workers. See :ref:`ddl`.

Type 3: Local Tables
~~~~~~~~~~~~~~~~~~~~

We have already mentioned the final type of tables: local metadata tables, which exist only on the coordinator node.

Shards
------

The previous section described a shard as containing a subset of the rows of a distributed table in a smaller table within a worker node. This section gets more into the technical details.

The :ref:`pg_dist_shard <pg_dist_shard>` metadata table on the coordinator contains a row for each shard of each distributed table in the system. The row matches a shardid with a range of integers in a hash space (shardminvalue, shardmaxvalue):

.. code-block:: sql

    SELECT * from pg_dist_shard;
     logicalrelid  | shardid | shardstorage | shardminvalue | shardmaxvalue 
    ---------------+---------+--------------+---------------+---------------
     github_events |  102026 | t            | 268435456     | 402653183
     github_events |  102027 | t            | 402653184     | 536870911
     github_events |  102028 | t            | 536870912     | 671088639
     github_events |  102029 | t            | 671088640     | 805306367
     (4 rows)

If the coordinator node wants to determine which shard holds a row of ``github_events``, it hashes the value of the distribution column in the row, and checks which shard's range contains the hashed value. (The ranges are defined so that the image of the hash function is their disjoint union.)

Shard Placements
~~~~~~~~~~~~~~~~

Suppose that shard 102027 is associated with the row in question. This means the row should be read or written to a table called ``github_events_102027`` in one of the workers. Which worker? That is determined entirely by the metadata tables, and the mapping of shard to worker is known as the shard *placement*.

.. code-block:: sql

  SELECT
      shardid,
      node.nodename,
      node.nodeport
  FROM pg_dist_placement placement
  JOIN pg_dist_node node
    ON placement.groupid = node.groupid
   AND node.noderole = 'primary'::noderole
  WHERE shardid = 102027;

  ┌─────────┬───────────┬──────────┐
  │ shardid │ nodename  │ nodeport │
  ├─────────┼───────────┼──────────┤
  │  102027 │ localhost │     5433 │
  └─────────┴───────────┴──────────┘

Joining some :ref:`metadata tables <metadata_tables>` gives us the answer. These are the types of lookups that the coordinator does to route queries. It rewrites queries into fragments that refer to the specific tables like ``github_events_102027``, and runs those fragments on the appropriate workers.

In our example of ``github_events`` there were four shards. The number of shards is configurable per table at the time of its distribution across the cluster. The best choice of shard count depends on your use case, see :ref:`prod_shard_count`.

Finally note that Citus allows shards to be replicated for protection against data loss. There are two replication "modes:" Citus replication and streaming replication. The former creates extra backup shard placements and runs queries against all of them that update any of them. The latter is more efficient and utilizes PostgreSQL's streaming replication to back up the entire database of each node to a follower database. This is transparent and does not require the involvement of Citus metadata tables.

Co-Location
-----------

Since shards and their replicas can be placed on nodes as desired, it makes sense to place shards containing related rows of related tables together on the same nodes. That way join queries between them can avoid sending as much information over the network, and can be performed inside a single Citus node.

For example, imagine an adventure game with players and their belongings. Distributing the ``player`` and ``player_item`` tables by the same type of column (bigint) and same number of shards (the default) puts them both into the same *colocation group.*

.. code-block:: sql

  CREATE TABLE player
  (
    id bigint PRIMARY KEY,
    name text,
    hit_points int,
    armor int
  );

  CREATE TABLE player_item
  (
    player_id bigint REFERENCES player (id),
    id bigint,
    title text,
    worth numeric(7,2),

    PRIMARY KEY (player_id, id)
  );

  SELECT create_distributed_table('player', 'id');
  SELECT create_distributed_table('player_item', 'player_id');

This means that a player and his items will be stored on shards located on the same workers. For instance, assume we had populated this table. Then this query would get player 1's name and net worth:

.. code-block:: sql

  EXPLAIN
  SELECT
      player.id,
      name,
      sum(worth) AS net_worth
  FROM
      player,
      player_item
  WHERE
      player.id = player_id
      AND player_id = 1
  GROUP BY
      player.id,
      name;

  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                QUERY PLAN                                                  │
  ├────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Custom Scan (Citus Router)  (cost=0.00..0.00 rows=0 width=0)                                               │
  │   Task Count: 1                                                                                            │
  │   Tasks Shown: All                                                                                         │
  │   ->  Task                                                                                                 │
  │     Node: host=localhost port=5434 dbname=citus                                                            │
  │     ->  GroupAggregate  (cost=4.33..20.88 rows=1 width=72)                                                 │
  │       Group Key: player.id                                                                                 │
  │       ->  Nested Loop  (cost=4.33..20.85 rows=4 width=54)                                                  │
  │         ->  Index Scan using player_pkey_102169 on player_102169 player  (cost=0.15..8.17 rows=1 width=40) │
  │               Index Cond: (id = 1)                                                                         │
  │         ->  Bitmap Heap Scan on player_item_102201 player_item  (cost=4.18..12.64 rows=4 width=22)         │
  │               Recheck Cond: (player_id = 1)                                                                │
  │           ->  Bitmap Index Scan on player_item_pkey_102201  (cost=0.00..4.18 rows=4 width=0)               │
  │                 Index Cond: (player_id = 1)                                                                │
  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

The keyword "Citus Router" in the EXPLAIN output indicates that this whole query was routed to one worker node and run there. The query passed from the coordinator to one worker and was able to run inside the single worker because the shards for the query were all available locally -- i.e. the tables were co-located.

For a full explanation and examples of this concept, see :ref:`colocation`.

Parallelism
-----------

Spreading queries across multiple machines allows more queries to run at once, and allows processing speed to scale by adding new machines to the cluster. Additionally splitting a single query into fragments as described in the previous section boosts the processing power devoted to it. The latter situation achieves the greatest *parallelism,* meaning utilization of CPU cores.

Queries reading or affecting shards spread evenly across many nodes are able to run at "real-time" speed. Note that the results of the query still need to pass back through the coordinator node, so the speedup is most apparent when the final results are compact, such as aggregate functions like counting and descriptive statistics.
