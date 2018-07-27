.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus supports all SQL queries on distributed tables, with only these exceptions:

* Correlated subqueries
* `Recursive <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_/`modifying <https://www.postgresql.org/docs/current/static/queries-with.html#QUERIES-WITH-MODIFYING>`_ CTEs
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_
* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_
* `Window functions <https://www.postgresql.org/docs/current/static/tutorial-window.html>`_ that do not include the distribution column in PARTITION BY

Furthermore, in :ref:`mt_use_case` when queries are filtered by table :ref:`dist_column` to a single tenant then all SQL features work, including the ones above.

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

.. _workarounds:

Workarounds
-----------

Before attempting workarounds consider whether Citus is appropriate for your
situation. Citus' current version works well for :ref:`real-time analytics and
multi-tenant use cases. <when_to_use_citus>`

Citus supports all SQL statements in the multi-tenant use-case. Even in the real-time analytics use-cases, with queries that span across nodes, Citus supports the majority of statements. The few types of unsupported queries are listed in :ref:`unsupported` Many of the unsupported features have workarounds; below are a number of the most useful.

.. _join_local_dist:

JOIN a local and a distributed table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Attempting to execute a JOIN between a local table "local" and a distributed table "dist" causes an error:

.. code-block:: sql

  SELECT * FROM local JOIN dist USING (id);

  /*
  ERROR:  relation local is not distributed
  STATEMENT:  SELECT * FROM local JOIN dist USING (id);
  ERROR:  XX000: relation local is not distributed
  LOCATION:  DistributedTableCacheEntry, metadata_cache.c:711
  */

Although you can't join such tables directly, by wrapping the local table in a subquery or CTE you can make Citus' recursive query planner copy the local table data to worker nodes. By colocating the data this allows the query to proceed.

.. code-block:: sql

  -- either

  SELECT *
    FROM (SELECT * FROM local) AS x
    JOIN dist USING (id);

  -- or

  WITH x AS (SELECT * FROM local)
  SELECT * FROM x
  JOIN dist USING (id);

Remember that the coordinator will send the results in the subquery or CTE to all workers which require it for processing. Thus it's best to either add the most specific filters and limits to the inner query as possible, or else aggregate the table. That reduces the network overhead which such a query can cause. More about this in :ref:`subquery_perf`.

.. _upsert_into_select:

INSERT…SELECT upserts lacking distribution column
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus supports INSERT…SELECT…ON CONFLICT statements between co-located tables when the distribution column is among those columns selected and inserted. Also aggregates in the statement must include the distribution column in the GROUP BY clause. Failing to meet these conditions will raise an error:

::

  ERROR: ON CONFLICT is not supported in INSERT ... SELECT via coordinator

If the upsert is an important operation in your application, the ideal solution is to model the data so that the source and destination tables are co-located, and so that the distribution column can be part of the GROUP BY clause in the upsert statement (if aggregating). However if this is not feasible then the workaround is to materialize the select query in a temporary distributed table, and upsert from there.

.. code-block:: postgresql

  -- workaround for
  -- INSERT INTO dest_table <query> ON CONFLICT <upsert clause>

  BEGIN;
  CREATE UNLOGGED TABLE temp_table (LIKE dest_table);
  SELECT create_distributed_table('temp_table', 'tenant_id');
  INSERT INTO temp_table <query>;
  INSERT INTO dest_table SELECT * FROM temp_table <upsert clause>;
  DROP TABLE temp_table;
  END;

Temp Tables: the Workaround of Last Resort
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are still a few queries that are :ref:`unsupported <unsupported>` even with the use of push-pull execution via subqueries. One of them is running window functions that partition by a non-distribution column.

Suppose we have a table called :code:`github_events`, distributed by the column :code:`user_id`. Then the following window function will not work:

.. code-block:: sql

  -- this won't work

  SELECT repo_id, org->'id' as org_id, count(*)
    OVER (PARTITION BY repo_id) -- repo_id is not distribution column
    FROM github_events
   WHERE repo_id IN (8514, 15435, 19438, 21692);

There is another trick though. We can pull the relevant information to the coordinator as a temporary table:

.. code-block:: sql

  -- grab the data, minus the aggregate, into a local table

  CREATE TEMP TABLE results AS (
    SELECT repo_id, org->'id' as org_id
      FROM github_events
     WHERE repo_id IN (8514, 15435, 19438, 21692)
  );

  -- now run the aggregate locally

  SELECT repo_id, org_id, count(*)
    OVER (PARTITION BY repo_id)
    FROM results;

Creating a temporary table on the coordinator is a last resort. It is limited by the disk size and CPU of the node.

Triggers on Distributed Tables
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus does not yet support creating triggers on distributed tables. As a workaround you can manually create triggers on table shards directly on the worker nodes. This works differently in different scenarios.

**Trigger against just one distributed table.**

Suppose that for each row in a table we wish to record the user who last updated it. We could add an ``author`` column to store who it was, and rather than make a default value for the column we could use a trigger. This prevents a user from overriding the record.

.. code-block:: postgresql

  CREATE TABLE events (
    id bigserial PRIMARY KEY,
    description text NOT NULL,
    author name NOT NULL
  );
  SELECT create_distributed_table('events', 'id');

However this is a distributed table, so a single trigger on the coordinator for the table won't work. We need to create a trigger for each of the table placements.

.. code-block:: postgresql

  -- First create a function that all these triggers will use.
  -- The function needs to be present on all workers.

  SELECT run_command_on_workers($cmd$
    CREATE OR REPLACE FUNCTION set_author() RETURNS TRIGGER AS $$
      BEGIN
        NEW.author := current_user;
        RETURN NEW;
      END;
    $$ LANGUAGE plpgsql;
  $cmd$);

  -- Now create a trigger for every placement

  SELECT run_command_on_placements(
    'events',
    $cmd$
      CREATE TRIGGER events_set_author BEFORE INSERT OR UPDATE ON %s
        FOR EACH ROW EXECUTE PROCEDURE set_author()
    $cmd$
  );

Now if we try to add fake data we will be prevented:

.. code-block:: postgresql

  INSERT INTO events (description,author) VALUES ('a bad thing', 'wasnt-me');

  TABLE events;

::

  ┌────┬─────────────┬────────┐
  │ id │ description │ author │
  ├────┼─────────────┼────────┤
  │  1 │ a bad thing │ citus  │
  └────┴─────────────┴────────┘

The author says "citus" rather than "wasnt-me."

**Trigger between colocated tables.**

When two distributed tables are :ref:`colocated <colocation>`, then we can create a trigger to modify one based on changes in the other. The idea, once again, is to create triggers on the placements, but the trigger must be between pairs of placements that are themselves colocated. For this Citus has a special helper function ``run_command_on_colocated_placements``.

Suppose that for every value inserted into ``little_vals`` we want to insert one twice as big into ``big_vals``.

.. code-block:: postgresql

  CREATE TABLE little_vals (key int, val int);
  CREATE TABLE big_vals    (key int, val int);
  SELECT create_distributed_table('little_vals', 'key');
  SELECT create_distributed_table('big_vals',    'key');

  -- This trigger function takes the destination placement as an argument

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

Then to test it:

.. code-block:: postgresql

  INSERT INTO little_vals VALUES (1, 42), (2, 101);
  TABLE big_vals;

::

  ┌─────┬─────┐
  │ key │ val │
  ├─────┼─────┤
  │   1 │  84 │
  │   2 │ 202 │
  └─────┴─────┘

**Trigger between reference tables.**

Reference tables are simpler than distributed tables in that they have exactly one shard which is replicated across all workers. To relate reference tables with a trigger, we simply need to create the trigger for the shard on all workers.

Suppose we want to record every change of ``insert_target`` in ``audit_table``, both of which are reference tables.

.. code-block:: postgresql

  -- create the reference tables

  CREATE TABLE insert_target (
    value text
  );
  CREATE TABLE audit_table(
    stamp timestamp,
    value text
  );
  SELECT create_reference_table('insert_target');
  SELECT create_reference_table('audit_table');

  -- now find the shard id for each table

  SELECT logicalrelid, shardid
  FROM pg_dist_shard
  WHERE logicalrelid IN
    ('insert_target'::regclass, 'audit_table'::regclass);

Include the shard ids (written below as "xxxxxx" and "yyyyyy") in custom queries:

.. code-block:: postgresql

  SELECT run_command_on_workers($cmd$
    CREATE OR REPLACE FUNCTION process_audit() RETURNS TRIGGER AS $$
      BEGIN
        INSERT INTO audit_table_xxxxxx(stamp,value) VALUES (now(),'value');
        RETURN NEW;
      END;
    $$ LANGUAGE plpgsql;
  $cmd$);

  SELECT run_command_on_workers($cmd$
    CREATE TRIGGER emp_audit
    AFTER INSERT OR UPDATE OR DELETE ON insert_target_yyyyyy
        EXECUTE PROCEDURE process_audit();
  $cmd$);

  EXPLAIN ANALYZE INSERT INTO insert_target (value) VALUES ('inserted value');

::

  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                       QUERY PLAN                                                        │
  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Custom Scan (Citus Router)  (cost=0.00..0.00 rows=0 width=0) (actual time=1.241..1.241 rows=0 loops=1)                  │
  │   Task Count: 1                                                                                                         │
  │   Tasks Shown: All                                                                                                      │
  │   ->  Task                                                                                                              │
  │         Node: host=localhost port=5433 dbname=postgres                                                                  │
  │         ->  Insert on insert_target_102681  (cost=0.00..0.01 rows=1 width=32) (actual time=0.033..0.033 rows=0 loops=1) │
  │               ->  Result  (cost=0.00..0.01 rows=1 width=32) (actual time=0.000..0.001 rows=1 loops=1)                   │
  │             Planning time: 0.017 ms                                                                                     │
  │             Trigger emp_audit: time=0.049 calls=1                                                                       │
  │             Execution time: 0.098 ms                                                                                    │
  │ Planning time: 0.064 ms                                                                                                 │
  │ Execution time: 1.272 ms                                                                                                │
  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

The EXPLAIN output shows that the trigger was called.
