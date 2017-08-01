Table Management
$$$$$$$$$$$$$$$$$$

.. _table_size:

Determining Table and Relation Size
###################################

The usual way to find table sizes in PostgreSQL, :code:`pg_total_relation_size`, drastically under-reports the size of distributed tables. All this function does on a Citus cluster is reveal the size of tables on the coordinator node. In reality the data in distributed tables lives on the worker nodes (in shards), not on the coordinator. A true measure of distributed table size is obtained as a sum of shard sizes. Citus provides helper functions to query this information.

+------------------------------------------+---------------------------------------------------------------+
| UDF                                      | Returns                                                       |
+==========================================+===============================================================+
| citus_relation_size(relation_name)       | * Size of actual data in table (the "`main fork <forks_>`_"). |
|                                          |                                                               |
|                                          | * A relation can be the name of a table or an index.          |
+------------------------------------------+---------------------------------------------------------------+
| citus_table_size(relation_name)          | * citus_relation_size plus:                                   |
|                                          |                                                               |
|                                          |    * size of `free space map <freemap_>`_                     |
|                                          |    * size of `visibility map <vismap_>`_                      |
+------------------------------------------+---------------------------------------------------------------+
| citus_total_relation_size(relation_name) | * citus_table_size plus:                                      |
|                                          |                                                               |
|                                          |    * size of indices                                          |
+------------------------------------------+---------------------------------------------------------------+

These functions are analogous to three of the standard PostgreSQL `object size functions <https://www.postgresql.org/docs/current/static/functions-admin.html#FUNCTIONS-ADMIN-DBSIZE>`_, with the additional note that

* They work only when :code:`citus.shard_replication_factor` = 1.
* If they can't connect to a node, they error out.

Here is an example of using one of the helper functions to list the sizes of all distributed tables:

.. code-block:: postgresql

  SELECT logicalrelid AS name,
         pg_size_pretty(citus_table_size(logicalrelid)) AS size
    FROM pg_dist_partition;

Output:

::

  ┌───────────────┬───────┐
  │     name      │ size  │
  ├───────────────┼───────┤
  │ github_users  │ 39 MB │
  │ github_events │ 37 MB │
  └───────────────┴───────┘

Vacuuming Distributed Tables
############################

In PostgreSQL (and other MVCC databases), an UPDATE or DELETE of a row does not immediately remove the old version of the row. The accumulation of outdated rows is called bloat and must be cleaned to avoid decreased query performance and unbounded growth of disk space requirements. PostgreSQL runs a process called the auto-vacuum daemon that periodically vacuums (aka removes) outdated rows.

It’s not just user queries which scale in a distributed database, vacuuming does too. In PostgreSQL big busy tables have great potential to bloat, both from lower sensitivity to PostgreSQL's vacuum scale factor parameter, and generally because of the extent of their row churn. Splitting a table into distributed shards means both that individual shards are smaller tables and that auto-vacuum workers can parallelize over different parts of the table on different machines. Ordinarily auto-vacuum can only run one worker per table.

Due to the above, auto-vacuum operations on a Citus cluster are probably good enough for most cases. However for tables with particular workloads, or companies with certain "safe" hours to schedule a vacuum, it might make more sense to manually vacuum a table rather than leaving all the work to auto-vacuum.

To vacuum a table, simply run this on the coordinator node:

.. code-block:: postgresql

  VACUUM my_distributed_table;

Using vacuum against a distributed table will send a vacuum command to every one of that table's placements (one connection per placement). This is done in parallel. All `options <https://www.postgresql.org/docs/current/static/sql-vacuum.html>`_ are supported (including the :code:`column_list` parameter) except for :code:`VERBOSE`. The vacuum command also runs on the coordinator, and does so before any workers nodes are notified. Note that unqualified vacuum commands (i.e. those without a table specified) do not propagate to worker nodes.

Analyzing Distributed Tables
############################

PostgreSQL's ANALYZE command collects statistics about the contents of tables in the database. Subsequently, the query planner uses these statistics to help determine the most efficient execution plans for queries.

The auto-vacuum daemon, discussed in the previous section, will automatically issue ANALYZE commands whenever the content of a table has changed sufficiently. The daemon schedules ANALYZE strictly as a function of the number of rows inserted or updated; it has no knowledge of whether that will lead to meaningful statistical changes. Administrators might prefer to manually schedule ANALYZE operations instead, to coincide with statistically meaningful table changes.

To analyze a table, run this on the coordinator node:

.. code-block:: postgresql

  ANALYZE my_distributed_table;

Citus propagates the ANALYZE command to all worker node placements.

Parallel Indexing
#################

Indexes are an essential tool for optimizing database performance and
are becoming ever more important with big data. However, as the volume
of data increases, index maintenance often becomes a write bottleneck,
especially for `advanced index
types <https://www.postgresql.org/docs/9.6/static/textsearch-indexes.html>`__
which use a lot of CPU time for every row that gets written. Index
creation may also become prohibitively expensive as it may take hours or
even days to build a new index on terabytes of data in PostgreSQL. Citus makes creating and maintaining indexes that much faster through parallelization.

Citus can be used to distribute PostgreSQL tables across many machines.
One of the many advantages of Citus is that you can keep adding more
machines with more CPUs such that you can keep increasing your write
capacity even if indexes are becoming the bottleneck. Citus allows ``CREATE INDEX`` to be performed in a massively parallel fashion,
allowing fast index creation on large tables. Moreover, the `COPY
command <https://www.postgresql.org/docs/current/static/sql-copy.html>`__
can write multiple rows in parallel when used on a distributed table,
which greatly improves performance for use-cases which can use bulk
ingestion (e.g. sensor data, click streams, telemetry).

To show the benefits of parallel indexing, we’ll walk through a small
example of indexing ~200k rows containing large JSON objects from the
`GitHub archive <https://www.githubarchive.org/>`__. To run the
examples, we set up a formation using `Citus
Cloud <https://console.citusdata.com/users/sign_up>`__ consisting of four
worker nodes with four cores each, running PostgreSQL 9.6.

You can download the sample data by running the following commands:

.. code-block:: bash

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..24}.csv.gz
    gzip -d github_events-*.gz

Next let's create the table for the GitHub events once as a regular
PostgreSQL table and then distribute it across the four nodes:

.. code-block:: postgresql

    CREATE TABLE github_events (
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

    -- (distributed table only) Shard the table by repo_id 
    SELECT create_distributed_table('github_events', 'repo_id');

    -- Initial data load: 218934 events from 2015-01-01
    \COPY github_events FROM PROGRAM 'cat github_events-*.csv' WITH (FORMAT CSV)

Each event in the GitHub data set has a detailed payload object in JSON
format. Building a GIN index on the payload gives us the ability to
quickly perform fine-grained searches on events, such as finding commits
from a specific author. However, building such an index can be very
expensive. Fortunately, parallel indexing makes this a lot faster by
using all cores at the same time and building many smaller indexes:

::

    CREATE INDEX github_events_payload_idx ON github_events USING GIN (payload);

    |                           | Regular table | Distributed table | Speedup |
    |---------------------------|---------------|-------------------|---------|
    | CREATE INDEX on 219k rows |         33.2s |              2.6s |     13x |

To test how well this scales we took the opportunity to run our test
multiple times. Interestingly, parallel ``CREATE INDEX`` exhibits
super-linear speedups giving >16x speedup despite having only 16 cores.
This is likely due to the fact that inserting into one big index is less
efficient than inserting into a small, per-shard index (following O(log
N) for N rows), which gives an additional performance benefit to
sharding.

::

    |                           | Regular table | Distributed table | Speedup |
    |---------------------------|---------------|-------------------|---------|
    | CREATE INDEX on 438k rows |         55.9s |              3.2s |     17x |
    | CREATE INDEX on 876k rows |        110.9s |              5.0s |     22x |
    | CREATE INDEX on 1.8M rows |        218.2s |              8.9s |     25x |

Once the index is created, the ``COPY`` command also takes advantage of
parallel indexing. Internally, COPY sends a large number of rows over
multiple connections to different workers asynchronously which then
store and index the rows in parallel. This allows for much faster load
times than a single PostgreSQL process could achieve. How much speedup
depends on the data distribution. If all data goes to a single
shard, performance will be very similar to PostgreSQL.

::

    \COPY github_events FROM PROGRAM 'cat github_events-*.csv' WITH (FORMAT CSV)

    |                         | Regular table | Distributed table | Speedup |
    |-------------------------|---------------|-------------------|---------|
    | COPY 219k rows no index |         18.9s |             12.4s |    1.5x |
    | COPY 219k rows with GIN |         49.3s |             12.9s |    3.8x |

Finally, it’s worth measuring the effect that the index has on query
time. We try two different queries, one across all repos and one with a
specific ``repo_id`` filter. This distinction is relevant to Citus
because the ``github_events`` table is sharded by ``repo_id``. A query
with a specific ``repo_id`` filter goes to a single shard, whereas the
other query is parallelised across all shards.

.. code-block:: postgresql

    -- Get all commits by test@gmail.com from all repos
    SELECT repo_id, jsonb_array_elements(payload->'commits')
      FROM github_events
     WHERE event_type = 'PushEvent' AND 
           payload @> '{"commits":[{"author":{"email":"test@gmail.com"}}]}';

    -- Get all commits by test@gmail.com from a single repo
    SELECT repo_id, jsonb_array_elements(payload->'commits')
      FROM github_events
     WHERE event_type = 'PushEvent' AND
           payload @> '{"commits":[{"author":{"email":"test@gmail.com"}}]}' AND
           repo_id = 17330407;

On 219k rows, this gives us the query times below. Times marked with \*
are of queries that are executed in parallel by Citus. Parallelisation
creates some fixed overhead, but also allows for more heavy lifting,
which is why it can either be much faster or a bit slower than queries
on a regular table.

::

    |                                       | Regular table | Distributed table |
    |---------------------------------------|---------------|-------------------|
    | SELECT no indexes, all repos          |         900ms |             68ms* |
    | SELECT with GIN on payload, all repos |           2ms |             11ms* |
    | SELECT no indexes, single repo        |         900ms |              28ms |
    | SELECT with indexes, single repo      |           2ms |               2ms |

Indexes in PostgreSQL can dramatically reduce query times, but at the
same time dramatically slow down writes. Citus gives you the possibility
of scaling out your cluster to get good performance on both sides of the
pipeline. A particular sweet spot for Citus is parallel ingestion and
single-shard queries, which gives querying performance that is better
than regular PostgreSQL, but with much higher and more scalable write
throughput.


.. _freemap: https://www.postgresql.org/docs/current/static/storage-fsm.html
.. _vismap: https://www.postgresql.org/docs/current/static/storage-vm.html
.. _forks: https://www.postgresql.org/docs/current/static/storage-file-layout.html
