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

.. _join_local_dist:

JOIN a local and a distributed table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This error no longer occurs in the current version of Citus unless the GUC
`citus.local_table_join_policy` is set to `never`.  By default, it is `auto`.
See the reference section for thie GUC for information about its possible
values.

When such joins are disabled (by explicitly setting
`citus.local_table_join_policy` to `never`), attempting to execute a JOIN
between a local table "local" and a distributed table "dist" will cause an
error:

.. code-block:: sql

  SELECT * FROM local JOIN dist USING (id);

  /*
  ERROR:  direct joins between distributed and local tables are not supported
  STATEMENT:  SELECT * FROM local JOIN dist USING (id);
  */

In that case, you need to set `citus.local_table_join_policy` back to `auto`
(or to another option provided) to enable this feature.

Remember that the coordinator will send the results in the subquery or CTE to
all workers which require it for processing. Thus it's best to either add the
most specific filters and limits to the inner query as possible, or else
aggregate the table. That reduces the network overhead which such a query can
cause. More about this in :ref:`subquery_perf`.

.. _join_local_ref:

JOIN a local and a reference table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Attempting to execute a JOIN between a local table "local" and a reference table "ref" causes an error:

.. code-block:: sql

  SELECT * FROM local JOIN ref USING (id);

::

  ERROR:  relation local is not distributed

Ordinarily a copy of every reference table exists on each worker node, but does not exist on the coordinator. Thus a reference table's data is not placed for efficient joins with tables local to the coordinator. To allow these kind of joins we can request that Citus place a copy of every reference table on the coordinator as well:

.. code-block:: postgres

  SELECT citus_add_node('localhost', 5432, groupid => 0);

This adds the coordinator to :ref:`pg_dist_node` with a group ID of 0. Joins between reference and local tables will then be possible.

If the reference tables are large there is a risk that they might exhaust the coordinator disk space. Use caution.

.. _change_dist_col:

Change a distribution column
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus does not allow DDL statements to alter distribution columns. The
workaround is to recreate the distributed table with an updated or different
distribution column.

There are two ways to recreate a distributed table:

1. "Undistribute" back to the coordinator, optionally make changes, and call
   :ref:`create_distributed_table` again.
2. Create a new distributed table with a different name, optionally make
   changes, and do a repartitioned insert-select into it. Drop the old table
   and rename the new one.

The first option is simpler, but works only when the data is small enough to
fit temporarily on the coordinator node. Also undistributing tables is not
allowed when they participate in foreign keys.

The second option is more complicated, but more efficient. The data moves
between worker nodes rather than accumulating on the coordinator node. Here's
an example of both methods. First create a table with two columns, and
distribute by the first column.

.. code-block:: postgres

  -- Example table
  create table items as
    select i, chr(ascii('a')+i%26) as t
      from generate_series(0,99) i;

  -- Distribute by 'i' column
  select create_distributed_table('items', 'i');

Now, using method 1, we'll distribute by the second column instead:

.. code-block:: postgres

  ----- Method 1 ---------------------------------------------------------

  -- Changing distribution column from 'i' to 't'

  -- First, undistribute. We can do this because there are no foreign keys
  -- from or to this table, and its data can fit on the coordinator node
  select undistribute_table('items');

  -- Simply distribute again, but by 't'
  select create_distributed_table('items', 't');

Here's the equivalent operation using method 2:

.. code-block:: postgres

  ----- Method 2 ---------------------------------------------------------

  -- Changing distribution column from 'i' to 't'

  -- Make a temporary table
  create table items2 (like items including all);

  -- Distribute new table by desired column
  select create_distributed_table('items2', 't');

  -- Copy data from items to items2, repartitioning across workers
  insert into items2 select * from items;

  -- Swap copy with original
  begin;
  drop table items;
  alter table items2 rename to items;
  commit;

Our example didn't involve foreign keys, but they would have to be
reconstructed after using either method. Method 1 in fact requires dropping the
foreign keys before undistributing.

Another complication when redistributing is that any uniqueness constraint must
include the distribution column.  For more about that see
:ref:`non_distribution_uniqueness`.

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
