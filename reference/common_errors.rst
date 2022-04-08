Common Error Messages
=====================

.. _error_failed_execute:

Could not receive query results
-------------------------------

Caused when the the coordinator node is unable to connect to a worker.

.. code-block:: sql

  SELECT 1 FROM companies WHERE id = 2928;

::

  ERROR:  connection to the remote node localhost:5432 failed with the following error: could not connect to server: Connection refused
          Is the server running on host "localhost" (127.0.0.1) and accepting
          TCP/IP connections on port 5432?


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

  ERROR:  canceling the transaction since it was involved in a distributed deadlock

Resolution
~~~~~~~~~~

Detecting deadlocks and stopping them is part of normal distributed transaction handling. It allows an application to retry queries or take another course of action.

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

SSL error: certificate verify failed
------------------------------------

As of Citus 8.1, nodes are required talk to one another using SSL by default. If SSL is not enabled on a Postgres server when Citus is first installed, the install process will enable it, which includes creating and self-signing an SSL certificate.

However, if a root certificate authority file exists (typically in ``~/.postgresql/root.crt``), then the certificate will be checked unsuccessfully against that CA at connection time. The Postgres documentation about `SSL support <https://www.postgresql.org/docs/current/libpq-ssl.html#LIBQ-SSL-CERTIFICATES>`_ warns:

   For backward compatibility with earlier versions of PostgreSQL,
   if a root CA file exists, the behavior of sslmode=require will be
   the same as that of verify-ca, meaning the server certificate is
   validated against the CA. Relying on this behavior is discouraged,
   and applications that need certificate validation should always use
   verify-ca or verify-full.

Resolution
~~~~~~~~~~

Possible solutions are to sign the certificate, turn off SSL, or remove the root certificate. Also a node may have trouble connecting to itself without the help of :ref:`local_hostname`.

Could not connect to any active placements
------------------------------------------

When all available worker connection slots are in use, further connections will fail.

::

  WARNING:  connection error: hostname:5432
  ERROR:  could not connect to any active placements

Resolution
~~~~~~~~~~

This error happens most often when copying data into Citus in parallel. The COPY command opens up one connection per shard. If you run M concurrent copies into a destination with N shards, that will result in M*N connections. To solve the error, reduce the shard count of target distributed tables, or run fewer ``\copy`` commands in parallel.

Remaining connection slots are reserved for non-replication superuser connections
---------------------------------------------------------------------------------

This occurs when PostgreSQL runs out of available connections to serve concurrent client requests.

Resolution
~~~~~~~~~~

The `max_connections <https://www.postgresql.org/docs/current/static/runtime-config-connection.html#GUC-MAX-CONNECTIONS>`_ GUC adjusts the limit, with a typical default of 100 connections. Note that each connection consumes resources, so adjust sensibly. When increasing ``max_connections`` it's usually a good idea to increase `memory limits <https://www.postgresql.org/docs/current/static/runtime-config-resource.html#RUNTIME-CONFIG-RESOURCE-MEMORY>`_ too.

Using `PgBouncer <https://pgbouncer.github.io/>`_ can also help by queueing connection requests which exceed the connection limit. (Our :ref:`cloud_topic` has a built-in PgBouncer instance.)

PgBouncer cannot connect to server
----------------------------------

In a self-hosted Citus cluster, this error indicates that the coordinator node is not responding to PgBouncer.

Resolution
~~~~~~~~~~

Try connecting directly to the server with psql to ensure it is running and accepting connections.

Relation *foo* is not distributed
---------------------------------

This error no longer occurs in the current version of Citus. It was caused by attempting to join local and distributed tables in the same query.

Resolution
~~~~~~~~~~

:ref:`Upgrade <upgrading>` to Citus 10.0 or higher.

Unsupported clause type
-----------------------

This error no longer occurs in the current version of Citus. It used to happen when executing a join with an inequality condition:

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

This error no longer occurs in the current version of Citus except in certain unusual shard repair scenarios. It used to happen when updating rows in a transaction, and then running another command which would open new coordinator-to-worker connections.

.. code-block:: postgresql

  BEGIN;
  -- run modification command that uses one connection
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

.. _non_distribution_uniqueness:

Cannot create uniqueness constraint
-----------------------------------

As a distributed system, Citus can guarantee uniqueness only if a unique index or primary key constraint includes a table's distribution column. That is because the shards are split so that each shard contains non-overlapping partition column values. The index on each worker node can locally enforce its part of the constraint.

Trying to make a unique index on a non-distribution column will generate an error:

::

  ERROR:  creating unique indexes on non-partition columns is currently unsupported

Enforcing uniqueness on a non-distribution column would require Citus to check every shard on every INSERT to validate, which defeats the goal of scalability.

Resolution
~~~~~~~~~~

There are two ways to enforce uniqueness on a non-distribution column:

1. Create a composite unique index or primary key that includes the desired column (*C*), but also includes the distribution column (*D*). This is not quite as strong a condition as uniqueness on *C* alone, but will ensure that the values of *C* are unique for each value of *D*. For instance if distributing by ``company_id`` in a multi-tenant system, this approach would make *C* unique within each company.
2. Use a :ref:`reference table <reference_tables>` rather than a hash distributed table. This is only suitable for small tables, since the contents of the reference table will be duplicated on all nodes.

Function create_distributed_table does not exist
------------------------------------------------

.. code-block:: sql

  SELECT create_distributed_table('foo', 'id');
  /*
  ERROR:  function create_distributed_table(unknown, unknown) does not exist
  LINE 1: SELECT create_distributed_table('foo', 'id');
  HINT:  No function matches the given name and argument types. You might need to add explicit type casts.
  */

Resolution
~~~~~~~~~~

When basic :ref:`user_defined_functions` are not available, check whether the Citus extension is properly installed. Running ``\dx`` in psql will list installed extensions.

One way to end up without extensions is by creating a new database in a Postgres server, which requires extensions to be re-installed. See :ref:`create_db` to learn how to do it right.

STABLE functions used in UPDATE queries cannot be called with column references
-------------------------------------------------------------------------------

Each PostgreSQL function is marked with a `volatility <https://www.postgresql.org/docs/current/static/xfunc-volatility.html>`_, which indicates whether the function can update the database, and whether the function's return value can vary over time given the same inputs. A ``STABLE`` function is guaranteed to return the same results given the same arguments for all rows within a single statement, while an ``IMMUTABLE`` function is guaranteed to return the same results given the same arguments forever.

Non-immutable functions can be inconvenient in distributed systems because they can introduce subtle changes when run at slightly different times across shards. Differences in database configuration across nodes can also interact harmfully with non-immutable functions.

One of the most common ways this can happen is using the ``timestamp`` type in Postgres, which unlike ``timestamptz`` does not keep a record of time zone. Interpreting a timestamp column makes reference to the database timezone, which can be changed between queries, hence functions operating on timestamps are not immutable.

Citus forbids running distributed queries that filter results using stable functions on columns. For instance:

.. code-block:: postgres

  -- foo_timestamp is timestamp, not timestamptz
  UPDATE foo SET ... WHERE foo_timestamp < now();

::

  ERROR:  STABLE functions used in UPDATE queries cannot be called with column references

In this case the comparison operator ``<`` between timestamp and timestamptz is not immutable.

Resolution
~~~~~~~~~~

Avoid stable functions on columns in a distributed UPDATE statement. In particular, whenever working with times use ``timestamptz`` rather than ``timestamp``. Having a time zone in timestamptz makes calculations immutable.
