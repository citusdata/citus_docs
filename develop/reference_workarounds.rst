.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus has 100% SQL coverage for any queries it is able to execute on a single worker node. These kind of queries are common in :ref:`mt_use_case` when accessing information about a single tenant.

Even cross-node queries (used for parallel computations) support most SQL features. However, some SQL features are not supported for queries which combine information from multiple nodes.

**Limitations for Cross-Node SQL Queries:**

* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_ work in single-shard queries only
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_ work in single-shard queries only
* Correlated subqueries are supported only when the correlation is on the :ref:`dist_column` and the subqueries conform to subquery pushdown rules (e.g., grouping by the distribution column, with no LIMIT or LIMIT OFFSET clause).
* Outer joins between distributed tables are only supported on the  :ref:`dist_column`
* Outer joins between distributed tables and reference tables or local tables are only supported if the distributed table is on the outer side
* `Recursive CTEs <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_ work in single-shard queries only
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`__ work in single-shard queries only

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_. For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

.. _workarounds:

Workarounds
-----------

Before attempting workarounds consider whether Citus is appropriate for your
situation. Citus' current version works well for :ref:`real-time analytics and
multi-tenant use cases. <when_to_use_citus>`

Citus supports all SQL statements in the multi-tenant use-case. Even in the real-time analytics use-cases, with queries that span across nodes, Citus supports the majority of statements. The few types of unsupported queries are listed in :ref:`unsupported` Many of the unsupported features have workarounds; below are a number of the most useful.

.. _pull_push_workaround:

Work around limitations using CTEs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When a SQL query is unsupported, one way to work around it is using CTEs, which use what we call pull-push execution.

.. code-block:: sql

  SELECT * FROM ref LEFT JOIN dist USING (id) WHERE dist.value > 10;
  /*
  ERROR:  cannot pushdown the subquery
  DETAIL:  There exist a reference table in the outer part of the outer join
  */

To work around this limitation, you can turn the query into a router query by wrapping the distributed part in a CTE

.. code-block:: sql

  WITH x AS (SELECT * FROM dist WHERE dist.value > 10)
  SELECT * FROM ref LEFT JOIN x USING (id);

Remember that the coordinator will send the results of the CTE to all workers which require it for processing. Thus it's best to either add the most specific filters and limits to the inner query as possible, or else aggregate the table. That reduces the network overhead which such a query can cause. More about this in :ref:`subquery_perf`.

Temp Tables: the Workaround of Last Resort
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are still a few queries that are :ref:`unsupported <unsupported>` even with the use of push-pull execution via subqueries. One of them is using `grouping sets <https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUPING-SETS>`__ on a distributed table.

In our :ref:`real-time analytics tutorial <real_time_analytics_tutorial>` we
created a table called :code:`github_events`, distributed by the column
:code:`user_id`. Let's query it and find the earliest events for a preselected
set of repos, grouped by combinations of event type and event publicity. A
convenient way to do this is with grouping sets. However, as mentioned, this
feature is not yet supported in distributed queries:

.. code-block:: sql

  -- this won't work

    SELECT repo_id, event_type, event_public,
           grouping(event_type, event_public),
           min(created_at)
      FROM github_events
     WHERE repo_id IN (8514, 15435, 19438, 21692)
  GROUP BY repo_id, ROLLUP(event_type, event_public);

::

  ERROR:  could not run distributed query with GROUPING
  HINT:  Consider using an equality filter on the distributed table's partition column.

There is a trick, though. We can pull the relevant information to the coordinator as a temporary table:

.. code-block:: sql

  -- grab the data, minus the aggregate, into a local table

  CREATE TEMP TABLE results AS (
    SELECT repo_id, event_type, event_public, created_at
      FROM github_events
         WHERE repo_id IN (8514, 15435, 19438, 21692)
      );

  -- now run the aggregate locally

    SELECT repo_id, event_type, event_public,
           grouping(event_type, event_public),
           min(created_at)
      FROM results
  GROUP BY repo_id, ROLLUP(event_type, event_public);

::

  .
   repo_id |    event_type     | event_public | grouping |         min
  ---------+-------------------+--------------+----------+---------------------
      8514 | PullRequestEvent  | t            |        0 | 2016-12-01 05:32:54
      8514 | IssueCommentEvent | t            |        0 | 2016-12-01 05:32:57
     19438 | IssueCommentEvent | t            |        0 | 2016-12-01 05:48:56
     21692 | WatchEvent        | t            |        0 | 2016-12-01 06:01:23
     15435 | WatchEvent        | t            |        0 | 2016-12-01 05:40:24
     21692 | WatchEvent        |              |        1 | 2016-12-01 06:01:23
     15435 | WatchEvent        |              |        1 | 2016-12-01 05:40:24
      8514 | PullRequestEvent  |              |        1 | 2016-12-01 05:32:54
      8514 | IssueCommentEvent |              |        1 | 2016-12-01 05:32:57
     19438 | IssueCommentEvent |              |        1 | 2016-12-01 05:48:56
     15435 |                   |              |        3 | 2016-12-01 05:40:24
     21692 |                   |              |        3 | 2016-12-01 06:01:23
     19438 |                   |              |        3 | 2016-12-01 05:48:56
      8514 |                   |              |        3 | 2016-12-01 05:32:54

Creating a temporary table on the coordinator is a last resort. It is limited by the disk size and CPU of the node.
