:orphan:

Controlling Query Propagation
#############################

When the user issues a query, the Citus coordinator partitions it into smaller query fragments where each query fragment can be run independently on a worker shard. This allows Citus to distribute each query across the cluster.

However the way queries are partitioned into fragments (and which queries are propagated at all) varies by the type of query. In some advanced situations it is useful to manually control this behavior. Citus provides utility functions to propagate SQL to workers, shards, or placements.

Manual query propagation bypasses coordinator logic, locking, and any other consistency checks. These functions are available as a last resort to allow statements which Citus otherwise does not run natively. Use them carefully to avoid data inconsistency and deadlocks.

.. _worker_propagation:

Running on all Workers
----------------------

The least granular level of execution is broadcasting a statement for execution on all workers. This is useful for viewing properties of entire worker databases or creating UDFs uniformly throughout the cluster. For example:

.. code-block:: postgresql

  -- Make a UDF available on all workers
  SELECT run_command_on_workers($cmd$ CREATE FUNCTION ... $cmd$);

  -- List the work_mem setting of each worker database
  SELECT run_command_on_workers($cmd$ SHOW work_mem; $cmd$);

.. note::

  The :code:`run_command_on_workers` function and other manual propagation commands in this section can run only queries which return a single column and single row.

Running on all Shards
---------------------

The next level of granularity is running a command across all shards of a particular distributed table. It can be useful, for instance, in reading the properties of a table directly on workers. Queries run locally on a worker node have full access to metadata such as table statistics.

The :code:`run_command_on_shards` function applies a SQL command to each shard, where the shard name is provided for interpolation in the command. Here is an example of estimating the row count for a distributed table by using the pg_class table on each worker to estimate the number of rows for each shard. Notice the :code:`%s` which will be replaced with each shard's name.

.. code-block:: postgresql

  -- Get the estimated row count for a distributed table by summing the
  -- estimated counts of rows for each shard.
  SELECT sum(result::bigint) AS estimated_count
  FROM run_command_on_shards(
    'my_distributed_table',
    $cmd$
      SELECT reltuples
        FROM pg_class c
        JOIN pg_catalog.pg_namespace n on n.oid=c.relnamespace
       WHERE n.nspname||'.'||relname = '%s';
    $cmd$
  );

Running on all Placements
-------------------------

The most granular level of execution is running a command across all shards and their replicas (aka :ref:`placements <placements>`). It can be useful for running data modification commands, which must apply to every replica to ensure consistency.

For example, suppose a distributed table has an :code:`updated_at` field, and we want to "touch" all rows so that they are marked as updated at a certain time. An ordinary UPDATE statement on the coordinator requires a filter by the distribution column, but we can manually propagate the update across all shards and replicas:

.. code-block:: postgresql

  -- note we're using a hard-coded date rather than
  -- a function such as "now()" because the query will
  -- run at slightly different times on each replica

  SELECT run_command_on_placements(
    'my_distributed_table',
    $cmd$
      UPDATE %s SET updated_at = '2017-01-01';
    $cmd$
  );

A useful companion to :code:`run_command_on_placements` is :code:`run_command_on_colocated_placements`. It interpolates the names of *two* placements of :ref:`co-located <colocation>` distributed tables into a query. The placement pairs are always chosen to be local to the same worker where full SQL coverage is available. Thus we can use advanced SQL features like triggers to relate the tables:

.. code-block:: postgresql

  -- Suppose we have two distributed tables
  CREATE TABLE little_vals (key int, val int);
  CREATE TABLE big_vals    (key int, val int);
  SELECT create_distributed_table('little_vals', 'key');
  SELECT create_distributed_table('big_vals',    'key');

  -- We want to synchronise them so that every time little_vals
  -- are created, big_vals appear with double the value
  --
  -- First we make a trigger function on each worker, which will
  -- take the destination table placement as an argument
  SELECT run_command_on_workers($cmd$
    CREATE OR REPLACE FUNCTION embiggen() RETURNS TRIGGER AS $$
      BEGIN
        IF (TG_OP = 'INSERT') THEN
          EXECUTE format(
            'INSERT INTO %s (key, val) SELECT ($1).key, ($1).val*2;',
            TG_ARGV[0]
          ) USING NEW;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
  $cmd$);

  -- Next we relate the co-located tables by the trigger function
  -- on each co-located placement
  SELECT run_command_on_colocated_placements(
    'little_vals',
    'big_vals',
    $cmd$
      CREATE TRIGGER after_insert AFTER INSERT ON %s
        FOR EACH ROW EXECUTE PROCEDURE embiggen(%s)
    $cmd$
  );

Limitations
-----------

* There are no safe-guards against deadlock for multi-statement transactions.
* There are no safe-guards against mid-query failures and resulting inconsistencies.
* Query results are cached in memory; these functions can't deal with very big result sets.
* The functions error out early if they cannot connect to a node.
* You can do very bad things!
