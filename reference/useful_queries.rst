.. _citus_sql_reference:

Useful Citus Queries 
####################

There are a number of queries that can be useful in monitoring your PostgreSQL cluster. Many of them, which provide things like cache hit rate or locks, are still valid in Citus, but may need to be adapted to run across all your nodes. This section contains a set of useful utility queries ready to run in a Citus cluster.

Detecting locks
---------------

This query will run across all worker nodes and identify locks, how long they've been open, and the offending queries:

.. code-block:: sql

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

Querying the size of your shards
--------------------------------

This query will provide you with the size of every shard of a given distributed table, designated here with the placeholder :code:`my_distributed_table`:

.. code-block:: sql

  SELECT pg_size_pretty(result::bigint)
  FROM run_command_on_shards('my_distributed_table', $cmd$
    SELECT pg_table_size('%s');
  $cmd$);

For more info about distributed table size, see :ref:`table_size`.

Identifying unused indices
--------------------------

This query will run across all worker nodes and identify any unused indexes for a given distributed table, designated here with the placeholder :code:`my_distributed_table`:

.. code-block:: sql

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

Monitoring client connection count
----------------------------------

This query will give you the connection count by each type that are open on the coordinator:

.. code-block:: sql

  SELECT state, count(*)
  FROM pg_stat_activity
  GROUP BY state;

Index hit rate
--------------

This query will provide you with your index hit rate across all nodes. Index hit rate is useful in determining how often indices are used when querying:

.. code-block:: sql

  SELECT nodename, result as index_hit_rate
  FROM run_command_on_workers($cmd$
    SELECT CASE sum(idx_blks_hit)
      WHEN 0 THEN 'NaN'::numeric
      ELSE to_char((sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit + idx_blks_read), '99.99')::numeric
      END AS ratio
    FROM pg_statio_user_indexes
  $cmd$);
