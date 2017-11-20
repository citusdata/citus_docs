.. _workarounds:

SQL Workarounds
===============

Before attempting workarounds consider whether Citus is appropriate for your
situation. Citus' current version works well for :ref:`real-time analytics and
multi-tenant use cases. <when_to_use_citus>`

Citus supports all SQL statements in the multi-tenant use-case. For real-time
analytics use-cases, with queries which span across nodes, Citus supports a
subset of SQL statements. We are continuously working to increase SQL coverage
to better support other use-cases such as data warehousing queries. Also many of
the unsupported features have workarounds; below are a number of the most useful.

Cross-Shard Aggregations in Views
---------------------------------

Internally PostgreSQL rewrites queries on views into queries using subqueries. Citus currently lacks support for cross-shard joins or aggregations in subqueries, so you will need a workaround for certain views.

For instance, suppose we have a table of todos with priorities:

.. code-block:: postgres

  CREATE TYPE prio AS ENUM ('low', 'med', 'high');

  CREATE TABLE todos (
    id serial,
    project_id int,
    priority prio DEFAULT 'med',
    what text NOT NULL,
    done boolean DEFAULT FALSE,
    PRIMARY KEY (id, project_id)
  );

First we'll load it with some medium priority tasks and then a handful of some with high priority.

.. code-block:: postgres

  INSERT INTO todos (project_id, what)
  SELECT random() * 4, 'usual thing'
  FROM generate_series(1, 100);

  INSERT INTO todos (project_id, what, priority)
  SELECT random() * 4, 'important thing', 'high'
  FROM generate_series(1, 10);

Then, we'll distribute the table by project id:

.. code-block:: postgres

  SELECT run_command_on_workers ($cmd$
    CREATE TYPE prio AS ENUM ('low', 'med', 'high');
  $cmd$);

  SELECT create_distributed_table ('todos', 'project_id');

An aggregate query works fine, but when run as a view it fails.

.. code-block:: postgres

  SELECT priority, count(*)
  FROM todos
  GROUP BY priority;

  ┌──────────┬───────┐
  │ priority │ count │
  ├──────────┼───────┤
  │ med      │   100 │
  │ high     │    10 │
  └──────────┴───────┘

  CREATE VIEW prio_count AS
  SELECT priority, count(*)
  FROM todos
  GROUP BY priority;

  SELECT * FROM prio_count;

  ERROR:  XX000: Unrecognized range table id 1
  LOCATION:  NewTableId, multi_physical_planner.c:1547

To solve the problem, we must restrict the view to a single shard. It will continue to aggregate by priority but we must filter it on the distribution column, project_id. One workaround is to make a similar view for each project as needed, like this one:

.. code-block:: postgres

  -- This view is specific to project 1

  CREATE VIEW prio_count_1 AS
  SELECT priority, count(*)
  FROM todos
  WHERE project_id = 1
  GROUP BY priority;

The same kind of workaround is required for views which join distributed tables by a non-distribution column.

Subqueries in WHERE
-------------------

A common type of query asks for values which appear in designated ways within a table, or aggregations of those values. For instance we might want to find which users caused events of types *A and B* in a table which records *one* user and event record per row:

.. code-block:: sql

  select user_id
    from events
   where event_type = 'A'
     and user_id in (
       select user_id
         from events
        where event_type = 'B'
     )

Another example. How many distinct sessions viewed the top twenty-five most visited web pages?

.. code-block:: sql

  select page_id, count(distinct session_id)
    from visits
   where page_id in (
     select page_id
       from visits
      group by page_id
      order by count(*) desc
      limit 25
   )
   group by page_id;

Citus does not allow subqueries in the WHERE clause so we must choose a workaround.

Workaround 1. Generate explicit WHERE-IN expression
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

*Best used when you don't want to complicate code in the application layer.*

In this technique we use PL/pgSQL to construct and execute one statement based on the results of another.

.. code-block:: postgresql

  -- create temporary table with results
  do language plpgsql $$
    declare user_ids bigint[];
  begin
    execute
      'select user_id'
      '  from events'
      ' where event_type = ''B'''
      into user_ids;
    execute format(
      'create temp table results_temp as '
      'select user_id'
      '  from events'
      ' where user_id = any(array[%s]::bigint[])'
      '   and event_type = ''A''',
      array_to_string(user_ids, ','));
  end;
  $$;

  -- read results, remove temp table
  select * from results_temp;
  drop table results_temp;

Workaround 2. Build query in SQL client
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

*Best used for simple cases when the subquery returns limited rows.*

Like the previous workaround this one creates an explicit list of values for an IN comparison. This workaround does too, except it does so in the application layer, not in the backend. It works best when there is a short list for the IN clause. For instance the page visits query is a good candidate because it limits its inner query to twenty-five rows.

.. code-block:: sql

  -- first run this
  select page_id
    from visits
   group by page_id
   order by count(*) desc
   limit 25;

Interpolate the list of ids into a new query

.. code-block:: sql

  -- Notice the explicit list of ids obtained from previous query
  -- and added by the application layer
  select page_id, count(distinct session_id)
    from visits
   where page_id in (2,3,5,7,13)
  group by page_id

JOIN a local and a distributed table
------------------------------------

Attempting to execute a JOIN between a local and a distributed table causes an error:

::

  ERROR: cannot plan queries that include both regular and partitioned relations

There is a workaround: you can replicate the local table to a single shard on every worker and push the join query down to the workers. We do this by defining the table as a 'reference' table using a different table creation API. Suppose we want to join tables *here* and *there*, where *there* is already distributed but *here* is on the coordinator database.


.. code-block:: sql

  SELECT create_reference_table('here');

This will create a table with a single shard (non-distributed), but will
replicate that shard to every node in the cluster. Now Citus will accept a join query between *here* and *there*, and each worker will have all the information it needs to work efficiently.

.. _window_func_workaround:

Window Functions
----------------

Currently Citus does not have out-of-the-box support for window functions on cross-shard queries, but there is a straightforward workaround. Window functions will work across shards on a distributed table if

1. The window function is in a subquery and
2. It includes a :code:`PARTITION BY` clause containing the table's distribution column

Suppose you have table called :code:`github_events`, distributed by the column :code:`user_id`. This query will **not** work directly:

.. code-block:: sql

  -- won't work, see workaround

  SELECT repo_id, org->'id' as org_id, count(*)
    OVER (PARTITION BY user_id)
    FROM github_events;

You can make it work by moving the window function into a subquery like this:

.. code-block:: sql

  SELECT *
  FROM (
    SELECT repo_id, org->'id' as org_id, count(*)
      OVER (PARTITION BY user_id)
      FROM github_events
  ) windowed;

Remember that it specifies :code:`PARTITION BY user_id`, the distribution column.

.. _data_warehousing_queries:

Data Warehousing Queries
------------------------

When queries have restrictive filters (i.e. when very few results need to be transferred to the coordinator) there is a general technique to run unsupported queries in two steps. First store the results of the inner queries in regular PostgreSQL tables on the coordinator. Then the next step can be executed on the coordinator like a regular PostgreSQL query.

For example, consider the :ref:`window_func_workaround` case above. If we're partitioning over a non-distribution column of a distributed table then the workaround mentioned in that section will not suffice.

.. code-block:: sql

  -- this won't work, not even with the subquery workaround

  SELECT repo_id, org->'id' as org_id, count(*)
  OVER (PARTITION BY repo_id) -- repo_id is not distribution column
  FROM github_events
  WHERE repo_id IN (8514, 15435, 19438, 21692);

We can use a more general trick though. We can pull the relevant information to the coordinator as a temporary table:

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

Similar workarounds can be found for other data warehousing queries involving unsupported constructs.

.. Note::

  The above query is a simple example intended at showing how meaningful workarounds exist around the lack of support for a few query types. Over time, we intend to support these commands out of the box within Citus.
