Controlling Query Propagation
#############################

When the user issues a query, the Citus coordinator partitions it into smaller query fragments where each query fragment can be run independently on a worker shard. This allows Citus to distribute each query across the cluster.

However the way queries are partitioned into fragments (and which queries are propagated at all) varies by the type of query. In some advanced situations it is useful to manually control this behavior. Citus provides utility functions to propagate SQL to workers, shards, or placements.

Running on all Workers
----------------------

The least granular level of execution is broadcasting a statement for execution on all workers. This is useful for viewing a properties of entire worker databases or creating UDFs uniformly throughout the cluster. For example:

.. code-block:: postgresql

  -- Make a UDF available on all workers
  SELECT run_command_on_workers($cmd$ CREATE FUNCTION ... $cmd$);

  -- List the work_mem setting of each worker database
  SELECT run_command_on_workers($cmd$ SHOW work_mem; $cmd$);

.. note::

  The :code:`run_command_on_workers` function and other manual propagation commands in this section can run only queries which return a single column and single row.

Running on all Shards
---------------------

Each distributed table :code:`foo` has shards across the workers which are each tables with a naming convention of :code:`foo_n` where :code:`n` is a number. In order to run a query against a shard, the query must be run on its containing worker, and the shard name must be interpolated into the query string as an identifier (:code:`%I`).

.. code-block:: postgresql

  -- Get the size of table shards to determine how balanced the cluster
  -- is. The third argument controls whether the queries are run in
  -- parallel and defaults to true
  SELECT *
    FROM run_command_on_shards(
      'my_distributed_table',
      $cmd$ SELECT pg_size_pretty(pg_total_relation_size('%I')) $cmd$,
      true
    );

  -- Get the total size of indices from all shards
  SELECT pg_size_pretty(sum(result::int))
    FROM run_command_on_shards(
      'my_distributed_table',
      $cmd$ SELECT pg_indexes_size('%I') $cmd$
    );

Running on all Placements
-------------------------

When using Citus- rather than streaming-replication for :ref:`dealing_with_node_failures`, each shard has replicas stored as tables on other workers. Shards and their replicas are all called *placements*. (PostgreSQL streaming replication, on the other hand, works at the database level rather than the shard level, so the notion of shard replica placements is not applicable there.)

Queries that update rows ought to be run on all placements rather than simply all shards. Ordinarily update queries go through the coordinator node which ensures they apply across placements. The functions in this section bypass the normal coordinator logic, so skipping any replicas in a manual update will leave the cluster inconsistent. Conversely, read-only queries should be run on shards rather than placements or they will return duplicate results.

The following are equivalent:

.. code-block:: postgresql

  -- ordinary query going through the coordinator
  UPDATE my_distributed_table
     SET some_col = some_col + 1;

  -- vs manually updating each placement
  SELECT run_command_on_placements(
    'my_distributed_table',
    $cmd$
      UPDATE %I SET some_col = some_col + 1
    $cmd$
  );

Whereas this next query leads to **inconsistency** for Citus-replication with replication factor greater than one:

.. code-block:: postgresql

  -- don't do this
  SELECT run_command_on_shards(
    'my_distributed_table',
    $cmd$
      UPDATE %I SET some_col = some_col + 1
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
  -- First we make a trigger function for each placement
  SELECT run_command_on_placements('big_vals', $cmd$
    CREATE OR REPLACE FUNCTION embiggen_%1$I() RETURNS TRIGGER AS $$
      BEGIN
        IF (TG_OP = 'INSERT') THEN
          INSERT INTO %1$I (key, val) VALUES (NEW.key, NEW.val*2);
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
      CREATE TRIGGER after_insert AFTER INSERT ON %I
        FOR EACH ROW EXECUTE PROCEDURE embiggen_%I()
    $cmd$
  );
