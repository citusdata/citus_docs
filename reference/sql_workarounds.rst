.. _workarounds:

SQL Workarounds
===============

Before attempting workarounds consider whether Citus is appropriate for your situation. Citus' current version works well for real-time analytics use cases. We are continuously working to increase SQL coverage to better support other use-cases such as data warehousing queries.

Citus supports most, but not all, SQL statements directly. Its SQL support continues to improve. Also many of the unsupported features have workarounds; below are a number of the most useful.

Subqueries in WHERE
-------------------

A common type of query asks for values which appear in designated ways within a table, or aggregations of those values. For instance we might want to find which users caused events of types A *and* B in a table which records one user and event record per row:

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
    select page_id from (
      select page_id, count(1) as total
        from visits
       group by page_id
       order by total desc
       limit 25
    ) as t
  )
  group by page_id

Citus does not allow subqueries in the WHERE clause so we must choose a workaround.

Workaround 1. Generate explicit WHERE-IN expression
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Pros
    * Able to distribute the query across shards
* Cons
    * Constructed query not suitable when facts subquery returns large number of results
    * Somewhat hard to read, requires building custom SQL

In this technique we use PL/pgSQL to construct and execute one statement based on the results of another. This workaround works best when there is a short list for the IN clause. For instance the page visits query is a good candidate because it limits its inner query to twenty-five rows.

.. code-block:: sql

  -- create temporary table with results
  do language plpgsql $$
    declare page_ids integer[];
  begin 
    execute
      'select page_id from ('
      '  select page_id, count(1) as total'
      '    from visits'
      '   group by page_id'
      '   order by total desc'
      '   limit 25'
      ') as t '
      'group by page_id'
      into page_ids;
    execute format(
      'create temp table results_temp as '
      'select page_id, count(distinct session_id)'
      '  from visits
      ' where page_id = any(array[%s])',
      array_to_string(page_ids, ','));
  end;
  $$;

  -- read results, remove temp table
  select * from results_temp;
  drop table results_temp;

Workaround 2. Build query in SQL client
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Pros
    * Able to distribute the query across shards
* Cons
    * Constructed query not suitable when facts subquery returns large number of results
    * Requires two query roundtrips to client

Like the previous workaround this one creates an explicit list of values for an IN comparison. The client obtains the list of items with one query, and uses it to construct the second query.

.. code-block:: sql

  -- first run this
  select page_id from (
    select page_id, count(1) as total
      from visits
     group by page_id
     order by total desc
     limit 25
  )

Interpolate the list of ids into a new query

.. code-block:: sql

  -- notice the explicit list of ids obtained from previous query
  select page_id, count(distinct session_id)
    from visits
   where page_id in (2,3,5,7,13)
  group by page_id

Workaround 3. Use a JOIN
~~~~~~~~~~~~~~~~~~~~~~~~

* Pros
    * Works for subqueries returning any number of results
* Cons
    * Can be inefficient if the JOIN requires data repartitioning

Sometimes you can convert a where-clause subquery to a (self) join. This is appropriate when the subquery returns a potentially large number of rows. Note that in the following example the group by clauses are workarounds for the lack of select distinct support as documented in another section.

.. code-block:: sql

  select user_id
  from (
    select a.user_id as user_id
    from (
      select user_id
        from events
       where event_type = 'A'
       group by user_id
      ) as a
    join (
      select user_id
        from events
       where event_Type = 'B'
       group by user_id
      ) as b
    on a.user_id = b.user_id
    group by user_id
  ) as inner_subquery;

INSERT INTO ... SELECT
----------------------

Citus does not support directly inserting the results of a query into a distributed table. One workaround is to use two database connections to stream the query results to master and then distribute them to the shards.

.. code-block:: bash

  psql -c "COPY (query) TO STDOUT" | psql -c "COPY table FROM STDIN"

This does incur network cost. If this workaround is too slow please contact Citus Data support. We can assist you in parallelizing the table insertion across all workers using a more complicated technique.

SELECT DISTINCT
---------------

Citus does not yet support SELECT DISTINCT but you can use GROUP BY for a simple workaround:

.. code-block:: sql

  -- rather than this
  -- select distinct col from table;

  -- use this
  select col from table group by col;

JOIN a local and a distributed table
------------------------------------

Attempting to execute a JOIN between a local and a distributed table causes an error:

::

  ERROR: cannot plan queries that include both regular and partitioned relations

In Citus Community and Enterprise editions there is a workaround. You can replicate the local table to a single shard on every worker and push the join query down to the workers. Suppose we want to join tables *here* and *there*, where *there* is already distributed but *here* is on the master database.

.. code-block:: sql

  -- Allow "here" to be distributed
  -- (presuming a primary key called "here_id")
  SELECT master_create_distributed_table('here', 'here_id', 'hash');

  -- Now make a full copy into a shard on every worker
  SELECT master_create_worker_shards(
    'here', 1,
    (SELECT count(1) from master_get_active_worker_nodes())::integer
  );

Now Citus will accept a join query between *here* and *there*, and each worker will have all the information it needs to work efficiently.

.. note::

  Citus Cloud uses PostgreSQL replication, not Citus replication, so this technique does not work there.

.. _data_warehousing_queries:

Data Warehousing Queries
------------------------

When queries have restrictive filters (i.e. when very few results need to be transferred to the master) there is a general technique to run unsupported queries in two steps. First store the results of the inner queries in regular PostgreSQL tables on the master. Then the next step can be executed on the master like a regular PostgreSQL query.

For example, currently Citus does not have out of the box support for window functions on queries involving distributed tables. Suppose you have a query with a window function on a table of github_events function like the following:

::

    select repo_id, actor->'id', count(*)
      over (partition by repo_id)
      from github_events
     where repo_id = 1 or repo_id = 2;

You can re-write the query like below:

Statement 1:

::

    create temp table results as (
      select repo_id, actor->'id' as actor_id
        from github_events
       where repo_id = 1 or repo_id = 2
    );

Statement 2:

::

    select repo_id, actor_id, count(*)
      over (partition by repo_id)
      from results;

Similar workarounds can be found for other data warehousing queries involving unsupported constructs.

.. Note::

  The above query is a simple example intended at showing how meaningful workarounds exist around the lack of support for a few query types. Over time, we intend to support these commands out of the box within Citus.
