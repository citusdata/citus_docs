.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus has 100% SQL coverage for any queries it is able to execute on a single worker node. These kind of queries are common in :ref:`mt_use_case` when accessing information about a single tenant.

Even cross-node queries (used for parallel computations) support most SQL features. However, some SQL features are not supported for queries which combine information from multiple nodes.

.. _limits:

Limitations
-----------

General
~~~~~~~

These limitations apply to all models of operation.

* The `rule system <https://www.postgresql.org/docs/current/rules.html>`_ is not supported
* :ref:`insert_subqueries_workaround` are not supported
* Distributing multi-level partitioned tables is not supported
* Functions used in UPDATE queries on distributed tables must not be VOLATILE
* STABLE functions used in UPDATE queries cannot be called with column references
* Modifying views when the query contains citus tables is not supported

Citus encodes the node identifier in the sequence generated on every node, this allows every individual node to take inserts directly without having the sequence overlap. This method however doesn't work for sequences that are smaller than BIGINT, which may result in inserts on worker nodes failing, in that case you need to drop the column and add a BIGINT based one, or route the inserts via the coordinator.

.. _cross_node_sql_limits:

Cross-Node SQL Queries
~~~~~~~~~~~~~~~~~~~~~~

* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_ work in single-shard queries only
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_ work in single-shard queries only
* Correlated subqueries are supported only when the correlation is on the :ref:`dist_column`
* Outer joins between distributed tables are only supported on the  :ref:`dist_column`
* `Recursive CTEs <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_ work in single-shard queries only
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`__ work in single-shard queries only
* Only regular, foreign or partitioned tables can be distributed
* The SQL `MERGE command <https://www.postgresql.org/docs/current/sql-merge.html>`_ is supported in the following combinations of :ref:`table_types`:

  =========== =========== =========== =========================================
  Target      Source      Support     Comments
  =========== =========== =========== =========================================
  Local       Local       Yes
  Local       Reference   Yes
  Local       Distributed No          Feature in development.
  Distributed Local       Yes
  Distributed Distributed Yes         Including non co-located tables.
  Distributed Reference   Yes
  Reference   N/A         No          Reference table as target is not allowed.
  =========== =========== =========== =========================================

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_. For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

.. _schema_based_sharding_limits:

Schema-based Sharding SQL compatibility
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When using :ref:`schema_based_sharding` the following features are not available:

* Foreign keys across distributed schemas are not supported
* Joins across distributed schemas are subject to :ref:`cross_node_sql_limits` limitations
* Creating a distributed schema and tables in a single SQL statement is not supported

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

  SELECT * FROM dist WHERE EXISTS (SELECT 1 FROM local WHERE local.a = dist.a);
  /*
  ERROR:  direct joins between distributed and local tables are not supported
  HINT:  Use CTE's or subqueries to select from local tables and use them in joins
  */

To work around this limitation, you can turn the query into a router query by wrapping the distributed part in a CTE

.. code-block:: sql

  WITH cte AS (SELECT * FROM dist)
  SELECT * FROM cte WHERE EXISTS (SELECT 1 FROM local WHERE local.a = cte.a);

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

.. _insert_subqueries_workaround:

Subqueries within INSERT queries
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Try rewriting your queries with 'INSERT INTO ... SELECT' syntax.

The following SQL:

.. code-block:: sql

  INSERT INTO a.widgets (map_id, widget_name)
  VALUES (
      (SELECT mt.map_id FROM a.map_tags mt WHERE mt.map_license = '12345'),
      'Test'
  );


Would become:

.. code-block:: sql

  INSERT INTO a.widgets (map_id, widget_name)
  SELECT mt.map_id, 'Test'
    FROM a.map_tags mt
   WHERE mt.map_license = '12345';
