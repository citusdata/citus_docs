Useful Diagnostic Queries
#########################

.. _row_placements:

Finding which shard contains data for a specific tenant
-------------------------------------------------------

The rows of a distributed table are grouped into shards, and each shard is placed on a worker node in the Citus cluster. In the multi-tenant Citus use case we can determine which worker node contains the rows for a specific tenant by putting together two pieces of information: the :ref:`shard id <get_shard_id>` associated with the tenant id, and the shard placements on workers. The two can be retrieved together in a single query. Suppose our multi-tenant application's tenants and are stores, and we want to find which worker node holds the data for Gap.com (id=4, suppose).

To find the worker node holding the data for store id=4, ask for the placement of rows whose distribution column has value 4:

.. code-block:: postgresql

  SELECT shardid, shardstate, shardlength, nodename, nodeport, placementid
    FROM pg_dist_placement AS placement,
         pg_dist_node AS node
   WHERE placement.groupid = node.groupid
     AND node.noderole = 'primary'
     AND shardid = (
       SELECT get_shard_id_for_distribution_column('stores', 4)
     );

The output contains the host and port of the worker database.

::

  ┌─────────┬────────────┬─────────────┬───────────┬──────────┬─────────────┐
  │ shardid │ shardstate │ shardlength │ nodename  │ nodeport │ placementid │
  ├─────────┼────────────┼─────────────┼───────────┼──────────┼─────────────┤
  │  102009 │          1 │           0 │ localhost │     5433 │           2 │
  └─────────┴────────────┴─────────────┴───────────┴──────────┴─────────────┘

.. _finding_dist_col:

Finding the distribution column for a table
-------------------------------------------

Each distributed table in Citus has a "distribution column." For more information about what this is and how it works, see :ref:`Distributed Data Modeling <distributed_data_modeling>`. There are many situations where it is important to know which column it is. Some operations require joining or filtering on the distribution column, and you may encounter error messages with hints like, "add a filter to the distribution column."

The :code:`pg_dist_*` tables on the coordinator node contain diverse metadata about the distributed database. In particular :code:`pg_dist_partition` holds information about the distribution column (formerly called *partition* column) for each table. You can use a convenient utility function to look up the distribution column name from the low-level details in the metadata. Here's an example and its output:

.. code-block:: postgresql

  -- create example table

  CREATE TABLE products (
    store_id bigint,
    product_id bigint,
    name text,
    price money,

    CONSTRAINT products_pkey PRIMARY KEY (store_id, product_id)
  );

  -- pick store_id as distribution column

  SELECT create_distributed_table('products', 'store_id');

  -- get distribution column name for products table

  SELECT column_to_column_name(logicalrelid, partkey) AS dist_col_name
    FROM pg_dist_partition
   WHERE logicalrelid='products'::regclass;

Example output:

::

  ┌───────────────┐
  │ dist_col_name │
  ├───────────────┤
  │ store_id      │
  └───────────────┘

Detecting locks
---------------

This query will run across all worker nodes and identify locks, how long they've been open, and the offending queries:

.. code-block:: postgresql

  SELECT * FROM citus_lock_waits;

For more information, see :ref:`dist_query_activity`.

Querying the size of your shards
--------------------------------

This query will provide you with the size of every shard of a given distributed table, designated here with the placeholder :code:`my_table`:

.. code-block:: postgresql

  SELECT shardid, table_name, shard_size
  FROM citus_shards
  WHERE table_name = 'my_table';

Example output:

::

  .
   shardid | table_name | shard_size
  ---------+------------+------------
    102170 | my_table   |   90177536
    102171 | my_table   |   90177536
    102172 | my_table   |   91226112
    102173 | my_table   |   90177536

This query uses the :ref:`citus_shards`.

Querying the size of all distributed tables
-------------------------------------------

This query gets a list of the sizes for each distributed table plus the size of their indices.

.. code-block:: postgresql

  SELECT table_name, table_size
    FROM citus_tables;

Example output:

::

  ┌───────────────┬────────────┐
  │  table_name   │ table_size │
  ├───────────────┼────────────┤
  │ github_users  │ 39 MB      │
  │ github_events │ 98 MB      │
  └───────────────┴────────────┘

There are other ways to measure distributed table size, as well. See :ref:`table_size`.

Identifying unused indices
--------------------------

This query will run across all worker nodes and identify any unused indexes for a given distributed table, designated here with the placeholder :code:`my_distributed_table`:

.. code-block:: postgresql

  SELECT *
  FROM run_command_on_shards('my_distributed_table', $cmd$
    SELECT array_agg(a) as infos
    FROM (
      SELECT (
        schemaname || '.' || relname || '##' || indexrelname || '##'
                   || pg_size_pretty(pg_relation_size(i.indexrelid))::text
                   || '##' || idx_scan::text
      ) AS a
      FROM  pg_stat_user_indexes ui
      JOIN  pg_index i
      ON    ui.indexrelid = i.indexrelid
      WHERE NOT indisunique
      AND   idx_scan < 50
      AND   pg_relation_size(relid) > 5 * 8192
      AND   (schemaname || '.' || relname)::regclass = '%s'::regclass
      ORDER BY
        pg_relation_size(i.indexrelid) / NULLIF(idx_scan, 0) DESC nulls first,
        pg_relation_size(i.indexrelid) DESC
    ) sub
  $cmd$);

Example output:

::

  ┌─────────┬─────────┬───────────────────────────────────────────────────────────────────────┐
  │ shardid │ success │                            result                                     │
  ├─────────┼─────────┼───────────────────────────────────────────────────────────────────────┤
  │  102008 │ t       │                                                                       │
  │  102009 │ t       │ {"public.my_distributed_table_102009##stupid_index_102009##28 MB##0"} │
  │  102010 │ t       │                                                                       │
  │  102011 │ t       │                                                                       │
  └─────────┴─────────┴───────────────────────────────────────────────────────────────────────┘

Monitoring client connection count
----------------------------------

This query will give you the connection count by each type that are open on the coordinator:

.. code-block:: sql

  SELECT state, count(*)
  FROM pg_stat_activity
  GROUP BY state;

Exxample output:

::

  ┌────────┬───────┐
  │ state  │ count │
  ├────────┼───────┤
  │ active │     3 │
  │ ∅      │     1 │
  └────────┴───────┘

Viewing system queries
----------------------

Active queries
~~~~~~~~~~~~~~

The ``citus_stat_activity`` view shows which queries are currently executing. You
can filter to find the actively executing ones, along with the process ID of
their backend:

.. code-block:: postgresql

  SELECT global_pid, query, state
    FROM citus_stat_activity
   WHERE state != 'idle';

Why are queries waiting
~~~~~~~~~~~~~~~~~~~~~~~

We can also query to see the most common reasons that non-idle queries that are
waiting. For an explanation of the reasons, check the `PostgreSQL documentation
<https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE>`_.

.. code-block:: postgresql

  SELECT wait_event || ':' || wait_event_type AS type, count(*) AS number_of_occurences
    FROM pg_stat_activity
   WHERE state != 'idle'
  GROUP BY wait_event, wait_event_type
  ORDER BY number_of_occurences DESC;

Example output when running ``pg_sleep`` in a separate query concurrently:

::

  ┌─────────────────┬──────────────────────┐
  │      type       │ number_of_occurences │
  ├─────────────────┼──────────────────────┤
  │ ∅               │                    1 │
  │ PgSleep:Timeout │                    1 │
  └─────────────────┴──────────────────────┘

Index hit rate
--------------

This query will provide you with your index hit rate across all nodes. Index hit rate is useful in determining how often indices are used when querying:

.. code-block:: postgresql

  -- on coordinator
  SELECT 100 * (sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit) AS index_hit_rate
    FROM pg_statio_user_indexes;

  -- on workers
  SELECT nodename, result as index_hit_rate
  FROM run_command_on_workers($cmd$
    SELECT 100 * (sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit) AS index_hit_rate
      FROM pg_statio_user_indexes;
  $cmd$);

Example output:

::

  ┌───────────┬────────────────┐
  │ nodename  │ index_hit_rate │
  ├───────────┼────────────────┤
  │ 10.0.0.16 │ 96.0           │
  │ 10.0.0.20 │ 98.0           │
  └───────────┴────────────────┘

Cache hit rate
--------------

Most applications typically access a small fraction of their total data at
once. Postgres keeps frequently accessed data in memory to avoid slow reads
from disk. You can see statistics about it in the `pg_statio_user_tables
<https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STATIO-ALL-TABLES-VIEW>`_
view.

An important measurement is what percentage of data comes from the memory cache
vs the disk in your workload:

.. code-block:: postgresql

  -- on coordinator
  SELECT
    sum(heap_blks_read) AS heap_read,
    sum(heap_blks_hit)  AS heap_hit,
    100 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS cache_hit_rate
  FROM
    pg_statio_user_tables;

  -- on workers
  SELECT nodename, result as cache_hit_rate
  FROM run_command_on_workers($cmd$
    SELECT
      100 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS cache_hit_rate
    FROM
      pg_statio_user_tables;
  $cmd$);

Example output:

::

  ┌───────────┬──────────┬─────────────────────┐
  │ heap_read │ heap_hit │   cache_hit_rate    │
  ├───────────┼──────────┼─────────────────────┤
  │         1 │      132 │ 99.2481203007518796 │
  └───────────┴──────────┴─────────────────────┘

If you find yourself with a ratio significantly lower than 99%, then you likely
want to consider increasing the cache available to your database
