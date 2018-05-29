Common Error Messages
=====================

.. _error_failed_execute:

Failed to execute task *n*
--------------------------

This happens when a task fails due to an issue on a particular worker node. For instance, consider a query that generally succeeds but raises an error on one of the workers:

.. code-block:: sql

  CREATE TABLE pageviews (
    page_id int,
    good_views int,
    total_views int
  );

  INSERT INTO pageviews
    VALUES (1, 50, 100), (2, 0, 0);

  SELECT create_distributed_table('pageviews', 'page_id');

  SELECT page_id,
    good_views / total_views AS goodness
  FROM pageviews;

The SELECT query fails:

::

  ERROR:  failed to execute task 50
  STATEMENT:  SELECT page_id, good_views/total_views AS goodness FROM pageviews;
  ERROR:  XX000: failed to execute task 50
  LOCATION:  MultiRealTimeExecute, multi_real_time_executor.c:255

To find out what's really going on, we have to examine the database logs inside worker nodes. In our case page_id=1 is stored on one worker and page_id=2 on another. The logs for the latter reveal:

::

  ERROR:  division by zero
  STATEMENT:  COPY (SELECT page_id, (good_views / total_views) AS goodness FROM pageviews_102480 pageviews WHERE true) TO STDOUT
  WARNING:  division by zero
  CONTEXT:  while executing command on localhost:5433
  WARNING:  22012: division by zero
  LOCATION:  ReportResultError, remote_commands.c:293

That's because ``total_views`` is zero in a row in shard ``pageviews_102480``.

Resolution
~~~~~~~~~~

Check the database logs on worker nodes to identify which query is failing. Common real-life causes for query failure on workers include invalid concatenation of jsonb objects, and typecasting errors. If PgBouncer is between the coordinator and workers, check that it is working properly as well.

Relation *foo* is not distributed
---------------------------------

This is caused by attempting to join local and distributed tables in the same query.

Resolution
~~~~~~~~~~

For an example, with workarounds, see :ref:`join_local_dist`.

Could not receive query results
-------------------------------

Caused when the :ref:`router_executor` on the coordinator node is unable to connect to a worker. (The :ref:`realtime_executor`, on the other hand, issues :ref:`error_failed_execute` in this situation.)

.. code-block:: sql

  SELECT 1 FROM companies WHERE id = 2928;

::

  WARNING:  connection error: ec2-52-21-20-100.compute-1.amazonaws.com:5432
  DETAIL:  no connection to the server
  ERROR:  could not receive query results

Resolution
~~~~~~~~~~

To fix, check that the worker is accepting connections, and that DNS is correctly resolving.

Canceling the transaction since it was involved in a distributed deadlock
-------------------------------------------------------------------------

Deadlocks can happen not only in a single-node database, but in a distributed database, caused by queries executing across multiple nodes. Citus has the intelligence to recognize distributed deadlocks and defuse them by aborting one of the queries involved.

We can see this in action by distributing rows across worker nodes, and then running two concurrent transactions with conflicting updates:

.. code-block:: sql

  CREATE TABLE lockme (id int, x int);
  SELECT create_distributed_table('lockme', 'id');

  -- id=1 goes to one worker, and id=2 another
  INSERT INTO lockme VALUES (1,1), (2,2);

  --------------- TX 1 ----------------  --------------- TX 2 ----------------
  BEGIN;
                                         BEGIN;
  UPDATE lockme SET x = 3 WHERE id = 1;
                                         UPDATE lockme SET x = 4 WHERE id = 2;
  UPDATE lockme SET x = 3 WHERE id = 2;
                                         UPDATE lockme SET x = 4 WHERE id = 1;

::

  ERROR:  40P01: canceling the transaction since it was involved in a distributed deadlock
  LOCATION:  ProcessInterrupts, postgres.c:2988

Resolution
~~~~~~~~~~

Detecting deadlocks and stopping them is part of normal distributed transaction handling. It allows an application to retry queries or take another course of action.

Cannot establish a new connection for placement *n*, since DML has been executed on a connection that is in use
---------------------------------------------------------------------------------------------------------------

.. code-block:: sql

  BEGIN;
  INSERT INTO http_request (site_id) VALUES (1337);
  INSERT INTO http_request (site_id) VALUES (1338);
  SELECT count(*) FROM http_request;

::

  ERROR:  25001: cannot establish a new connection for placement 314, since DML has been executed on a connection that is in use
  LOCATION:  FindPlacementListConnection, placement_connection.c:612

This is a current limitation. In a single transaction Citus does not support running insert/update statements with the :ref:`router_executor` that reference multiple shards, followed by a read query that consults both of the shards.

Resolution
~~~~~~~~~~

Consider moving the read query into a separate transaction.

Could not connect to server: Cannot assign requested address
------------------------------------------------------------

::

  WARNING:  connection error: localhost:9703
  DETAIL:  could not connect to server: Cannot assign requested address

This occurs when there are no more sockets available by which the coordinator can respond to worker requests.

Resolution
~~~~~~~~~~

Configure the operating system to re-use TCP sockets. Execute this on the shell in the coordinator node:

.. code-block:: bash

  sysctl -w net.ipv4.tcp_tw_reuse=1

This allows reusing sockets in TIME_WAIT state for new connections when it is safe from a protocol viewpoint. Default value is 0 (disabled).

Remaining connection slots are reserved for non-replication superuser connections
---------------------------------------------------------------------------------

This occurs when PostgreSQL runs out of available connections to serve concurrent client requests.

Resolution
~~~~~~~~~~

The `max_connections <https://www.postgresql.org/docs/current/static/runtime-config-connection.html#GUC-MAX-CONNECTIONS>`_ GUC adjusts the limit, with a typical default of 100 connections. Note that each connection consumes resources, so adjust sensibly. When increasing ``max_connections`` it's usually a good idea to increase `memory limits <https://www.postgresql.org/docs/current/static/runtime-config-resource.html#RUNTIME-CONFIG-RESOURCE-MEMORY>`_ too.

Using `PgBouncer <https://pgbouncer.github.io/>`_ can also help by queueing connection requests which exceed the connection limit. Citus Cloud has a built-in PgBouncer instance, see :ref:`cloud_pgbouncer` to learn how to connect through it.

PgBouncer cannot connect to server
----------------------------------

In a self-hosted Citus cluster, this error indicates that the coordinator node is not responding to PgBouncer.

Resolution
~~~~~~~~~~

Try connecting directly to the server with psql to ensure it is running and accepting connections.

Unsupported clause type
-----------------------

This error no longer occurs in the current version of citus. It used to happen when executing a join with an inequality condition:

.. code-block:: postgresql

  SELECT *
   FROM identified_event ie
   JOIN field_calculator_watermark w ON ie.org_id = w.org_id
  WHERE w.org_id = 42
    AND ie.version > w.version
  LIMIT 10;

::

  ERROR:  unsupported clause type

Resolution
~~~~~~~~~~

:ref:`Upgrade <upgrading>` to Citus 7.2 or higher.

Cannot open new connections after the first modification command within a transaction
-------------------------------------------------------------------------------------

This error no longer occurs in the current version of citus except in certain unusual shard repair scenarios. It used to happen when updating rows in a transaction, and then running another command which would open new coordinator-to-worker connections.

.. code-block:: postgresql

  BEGIN;
  -- run modification command that uses one connection via
  -- the router executor
  DELETE FROM http_request
   WHERE site_id = 8
     AND ingest_time < now() - '1 week'::interval;

  -- now run a query that opens connections to more workers
  SELECT count(*) FROM http_request;

::

  ERROR:  cannot open new connections after the first modification command within a transaction


Resolution
~~~~~~~~~~

:ref:`Upgrade <upgrading>` to Citus 7.2 or higher.

ON CONFLICT is not supported via coordinator
--------------------------------------------

Running an INSERT…SELECT statement with an ON CONFLICT clause will fail unless the source and destination tables are co-located, and unless the distribution column is among the columns selected from the source and inserted in the destination. Also if there is a GROUP BY clause it must include the distribution column. Failing to meet these conditions will raise an error:

::

  ERROR: ON CONFLICT is not supported in INSERT ... SELECT via coordinator

Resolution
~~~~~~~~~~

Add the table distribution column to both the select and insert statements, as well as the statement GROUP BY if applicable. For more info as well as a workaround, see :ref:`upsert_into_select`.
