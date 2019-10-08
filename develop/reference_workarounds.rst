.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus has 100% SQL coverage for any queries it is able to execute on a single worker node. These kind of queries are common in :ref:`mt_use_case` when accessing information about a single tenant.

Even cross-node queries (used for parallel computations) support most SQL features. However some SQL features are not supported for queries which combine information from multiple nodes.

**Limitations for Cross-Node SQL Queries:**

* `Window functions <https://www.postgresql.org/docs/current/static/tutorial-window.html>`_ are supported only when they include the distribution column in PARTITION BY.
* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_ work in single-shard queries only
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_ work in single-shard queries only
* Correlated subqueries are supported only when the correlation is on the :ref:`dist_column` and the subqueries conform to subquery pushdown rules (e.g., grouping by the distribution column, with no LIMIT or LIMIT OFFSET clause).
* `Recursive CTEs <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_ work in single-shard queries only
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_ work in single-shard queries only

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_. For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

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

Temp Tables: the Workaround of Last Resort
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are still a few queries that are :ref:`unsupported <unsupported>` even with the use of push-pull execution via subqueries. One of them is running window functions that partition by a non-distribution column.

In our :ref:`real-time analytics tutorial <real_time_analytics_tutorial>` we created a table called :code:`github_events`, distributed by the column :code:`user_id`. If we want to query it and count the events for a preselected of repos, one way to do it in SQL is with a window function. However, partitioning on a non-distribution column does not work:

.. code-block:: sql

  -- this won't work

  SELECT repo_id, org->'id' as org_id, count(*)
    OVER (PARTITION BY repo_id) -- repo_id is not distribution column
    FROM github_events
   WHERE repo_id IN (8514, 15435, 19438, 21692);

There is a trick, though. We can pull the relevant information to the coordinator as a temporary table:

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
