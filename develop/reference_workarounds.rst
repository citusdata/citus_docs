.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus supports all SQL queries on distributed tables, with a few exceptions.

Not yet supported:

* `Recursive CTEs <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_

Partially supported:

* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_ are supported for :ref:`router_executor` queries.
* `Window functions <https://www.postgresql.org/docs/current/static/tutorial-window.html>`_ are supported when they include the distribution column in PARTITION BY.
* Correlated subqueries are supported when the correlation is on the :ref:`dist_column` and the subqueries conform to subquery pushdown rules (e.g., grouping by the distribution column, with no LIMIT or LIMIT OFFSET clause).

Furthermore, in :ref:`mt_use_case` when queries are filtered by table :ref:`dist_column` to a single tenant then all SQL features work, including the ones above.

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

