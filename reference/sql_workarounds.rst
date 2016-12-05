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

.. code-block:: sql

  -- create temporary table with results
  do language plpgsql $$
    declare user_ids integer[];
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
      ' where user_id = any(array[%s])'
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

In Citus Community and Enterprise editions there is a workaround. You can
replicate the local table to a single shard on every worker and push the join
query down to the workers. We do this by defining the table as a 'reference'
table using a different table creation API and setting
citus.shard_replication_factor to the current number of worker nodes. Suppose we
want to join tables *here* and *there*, where *there* is already distributed but
*here* is on the master database.


.. code-block:: sql

  -- First get the number of current active worker nodes
  SELECT count(1) FROM master_get_active_worker_nodes();
  
  SET citus.shard_replication_factor = <number of nodes>
  
  SELECT create_reference_table('here');

This will create a table with a single shard (non-distributed), but will
replicate that shard to every node in the cluster. Now Citus will accept a join query between *here* and *there*, and each worker will have all the information it needs to work efficiently.

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
