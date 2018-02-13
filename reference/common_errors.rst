Commonly Encountered Error Messages
===================================

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

Common real-life causes for worker failures include PgBouncer failure, invalid concatenation of jsonb objects, and typecasting errors.

Relation *foo* is not distributed
---------------------------------

This is caused by attempting to mix local and distributed tables in the same query. For an example, with workarounds, see :ref:`join_local_dist`.

Could not receive query results
-------------------------------

Caused when the :ref:`router_executor` on the coordinator node is unable to connect to a worker. (The :ref:`realtime_executor`, on the other hand, issues :ref:`error_failed_execute` in this situation.)

.. code-block:: sql

  SELECT 1 FROM companies WHERE id = 2928;

::

  WARNING:  connection error: ec2-52-21-20-100.compute-1.amazonaws.com:5432
  DETAIL:  no connection to the server
  ERROR:  could not receive query results

To fix, check that the worker is running, and that DNS is correctly resolving.

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

Could not connect to server: Cannot assign requested address
------------------------------------------------------------

::

  WARNING:  connection error: localhost:9703
  DETAIL:  could not connect to server: Cannot assign requested address

This occurs when there are no more sockets available by which the coordinator can respond to worker requests. It can be mitigated by re-using TCP sockets at the OS level. Execute this on the shell in the coordinator node:

.. code-block:: bash

  sysctl -w net.ipv4.tcp_tw_reuse=1

Remaining connection slots are reserved for non-replication superuser connections
---------------------------------------------------------------------------------

(Citus Cloud error.)

This occurs when Citus Cloud runs out of available connections. See :ref:`cloud_pgbouncer` to learn how to connect through Cloud's built-in PgBouncer instance to queue incoming connections.

PgBouncer cannot connect to server
----------------------------------

In a self-hosted Citus cluster, this error indicates that the coordinator node is not responding to PgBouncer. Check the health of the server.
