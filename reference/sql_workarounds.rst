.. _workarounds:

SQL Workarounds
===============

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

Workaround 1½. Build query in SQL client
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

Workaround 2. Duplicate on Master
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Pros
    * Works for subqueries returning any number of results
* Cons
    * Must transmit full rows from the queries back to the master

In this workaround the client runs the outer- and sub-query independently, saves their results, and joins them.

.. code-block:: sql

  -- Capture the dimension query results
  create temp table dim_temp as
  select fact_id, dim_a, dim_b, dim_c
    from dimensions
   where ...conditions...;
  
  -- Capture the subquery results
  create temp table fact_temp as
  select id
    from facts
   where ...conditions...;
  
  -- Run the query on local tables where subqueries are OK
  select dim_a, dim_b, dim_c
    from dim_temp
   where fact_id in (select id from fact_temp);

  -- Remove temp tables
  drop table dim_temp;
  drop table fact_temp;

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
