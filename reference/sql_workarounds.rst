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

.. _join_local_dist:

JOIN a local and a distributed table
------------------------------------

Attempting to execute a JOIN between a local table "local" and a distributed table "dist" causes an error:

.. code-block:: sql

  SELECT * FROM local JOIN dist USING (id);

  /*
  ERROR:  relation local is not distributed
  STATEMENT:  SELECT * FROM local JOIN dist USING (id);
  ERROR:  XX000: relation local is not distributed
  LOCATION:  DistributedTableCacheEntry, metadata_cache.c:711
  */

Although you can't join such tables directly, by wrapping the local table in a subquery or CTE you can make Citus' recursive query planner copy the local table to a temporary table on worker nodes. By colocating the data this allows the query to proceed.

.. code-block:: sql

  -- either

  SELECT *
    FROM (SELECT * FROM local) AS x
    JOIN dist USING (id);

  -- or

  WITH x AS (SELECT * FROM local)
  SELECT * FROM x
  JOIN dist USING (id);

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
