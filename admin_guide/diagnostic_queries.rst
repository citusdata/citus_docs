Useful Diagnostic Queries
#########################

.. _row_placements:

Finding which shard contains data for a specific tenant
-------------------------------------------------------

The rows of a distributed table are grouped into shards, and each shard is placed on a worker node in the Citus cluster. In the multi-tenant Citus use case we can determine which worker node contains the rows for a specific tenant by putting together two pieces of information: the :ref:`shard id <get_shard_id>` associated with the tenant id, and the shard placements on workers. The two can be retrieved together in a single query. Suppose our multi-tenant application's tenants and are stores, and we want to find which worker node holds the data for Gap.com (id=4, suppose).

To find the worker node holding the data for store id=4, ask for the placement of rows whose distribution column has value 4:

.. code-block:: postgresql

  SELECT *
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

  SELECT run_command_on_workers($cmd$
    SELECT array_agg(
      blocked_statement || ' $ ' || cur_stmt_blocking_proc
      || ' $ ' || cnt::text || ' $ ' || age
    )
    FROM (
      SELECT blocked_activity.query    AS blocked_statement,
             blocking_activity.query   AS cur_stmt_blocking_proc,
             count(*)                  AS cnt,
             age(now(), min(blocked_activity.query_start)) AS "age"
      FROM pg_catalog.pg_locks         blocked_locks
      JOIN pg_catalog.pg_stat_activity blocked_activity
        ON blocked_activity.pid = blocked_locks.pid
      JOIN pg_catalog.pg_locks         blocking_locks
        ON blocking_locks.locktype = blocked_locks.locktype
       AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
       AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
       AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
       AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
       AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
       AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
       AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
       AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
       AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
       AND blocking_locks.pid != blocked_locks.pid
      JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
      WHERE NOT blocked_locks.GRANTED
       AND blocking_locks.GRANTED
      GROUP BY blocked_activity.query,
               blocking_activity.query
      ORDER BY 4
    ) a
  $cmd$);

Example output:

::

  ┌───────────────────────────────────────────────────────────────────────────────────┐
  │                               run_command_on_workers                              │
  ├───────────────────────────────────────────────────────────────────────────────────┤
  │ (localhost,5433,t,"")                                                             │
  │ (localhost,5434,t,"{""update ads_102277 set name = 'new name' where id = 1; $ sel…│
  │…ect * from ads_102277 where id = 1 for update; $ 1 $ 00:00:03.729519""}")         │
  └───────────────────────────────────────────────────────────────────────────────────┘

Querying the size of your shards
--------------------------------

This query will provide you with the size of every shard of a given distributed table, designated here with the placeholder :code:`my_distributed_table`:

.. code-block:: postgresql

  SELECT *
  FROM run_command_on_shards('my_distributed_table', $cmd$
    SELECT json_build_object(
      'shard_name', '%1$s',
      'size',       pg_size_pretty(pg_table_size('%1$s'))
    );
  $cmd$);

Example output:

::

  ┌─────────┬─────────┬───────────────────────────────────────────────────────────────────────┐
  │ shardid │ success │                                result                                 │
  ├─────────┼─────────┼───────────────────────────────────────────────────────────────────────┤
  │  102008 │ t       │ {"shard_name" : "my_distributed_table_102008", "size" : "2416 kB"}    │
  │  102009 │ t       │ {"shard_name" : "my_distributed_table_102009", "size" : "3960 kB"}    │
  │  102010 │ t       │ {"shard_name" : "my_distributed_table_102010", "size" : "1624 kB"}    │
  │  102011 │ t       │ {"shard_name" : "my_distributed_table_102011", "size" : "4792 kB"}    │
  └─────────┴─────────┴───────────────────────────────────────────────────────────────────────┘

Querying the size of all distributed tables
-------------------------------------------

This query gets a list of the sizes for each distributed table plus the size of their indices.

.. code-block:: postgresql

  SELECT
    tablename,
    pg_size_pretty(
      citus_total_relation_size(tablename::text)
    ) AS total_size
  FROM pg_tables pt
  JOIN pg_dist_partition pp
    ON pt.tablename = pp.logicalrelid::text
  WHERE schemaname = 'public';

Example output:

::

  ┌───────────────┬────────────┐
  │   tablename   │ total_size │
  ├───────────────┼────────────┤
  │ github_users  │ 39 MB      │
  │ github_events │ 98 MB      │
  └───────────────┴────────────┘

Note that this query works only when :code:`citus.shard_replication_factor` = 1. Also there are other Citus functions for querying distributed table size, see :ref:`table_size`.

Detetermining Replication Factor per Table
------------------------------------------

When using Citus replication rather than PostgreSQL streaming replication, each table can have a customized "replication factor." This controls the number of redundant copies Citus keeps of each of the table's shards. (See :ref:`worker_node_failures`.)

To see an overview of this setting for all tables, run:

.. code-block:: postgresql

  SELECT logicalrelid AS tablename,
         count(*)/count(DISTINCT ps.shardid) AS replication_factor
  FROM pg_dist_shard_placement ps
  JOIN pg_dist_shard p ON ps.shardid=p.shardid
  GROUP BY logicalrelid;

Example output:

::

  ┌───────────────┬────────────────────┐
  │   tablename   │ replication_factor │
  ├───────────────┼────────────────────┤
  │ github_events │                  1 │
  │ github_users  │                  1 │
  └───────────────┴────────────────────┘

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
      AND   schemaname || '.' || relname = '%s'
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

Index hit rate
--------------

This query will provide you with your index hit rate across all nodes. Index hit rate is useful in determining how often indices are used when querying:

.. code-block:: postgresql

  SELECT nodename, result as index_hit_rate
  FROM run_command_on_workers($cmd$
    SELECT CASE sum(idx_blks_hit)
      WHEN 0 THEN 'NaN'::numeric
      ELSE to_char((sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit + idx_blks_read), '99.99')::numeric
      END AS ratio
    FROM pg_statio_user_indexes
  $cmd$);

Example output:

::

  ┌───────────────────────────────────────────────────┬────────────────┐
  │                     nodename                      │ index_hit_rate │
  ├───────────────────────────────────────────────────┼────────────────┤
  │ ec2-13-59-96-221.us-east-2.compute.amazonaws.com  │ 0.88           │
  │ ec2-52-14-226-167.us-east-2.compute.amazonaws.com │ 0.89           │
  └───────────────────────────────────────────────────┴────────────────┘
