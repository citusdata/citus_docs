.. _cluster_management:

Cluster Management
##################

In this section, we discuss how you can add or remove nodes from your Citus cluster and how you can deal with node failures.

.. note::
  To make moving shards across nodes or re-replicating shards on failed nodes easier, our :ref:`cloud_topic` comes with a shard rebalancer extension. We discuss briefly about the functions provided by the shard rebalancer as and when relevant in the sections below. You can learn more about these functions, their arguments and usage, in the :ref:`cluster_management_functions` reference section.

.. _production_sizing:

Choosing Cluster Size
=====================

This section explores configuration settings for running a cluster in production.

.. _prod_shard_count:

Shard Count
-----------

Choosing the shard count for each distributed table is a balance between the flexibility of having more shards, and the overhead for query planning and execution across them. If you decide to change the shard count of a table after distributing, you can use the :ref:`alter_distributed_table` function.

Multi-Tenant SaaS Use-Case
~~~~~~~~~~~~~~~~~~~~~~~~~~

The optimal choice varies depending on your access patterns for the data. For instance, in the :ref:`mt_blurb` use-case we recommend choosing between **32 - 128 shards**.  For smaller workloads say <100GB, you could start with 32 shards and for larger workloads you could choose 64 or 128. This means that you have the leeway to scale from 32 to 128 worker machines.

Real-Time Analytics Use-Case
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the :ref:`rt_blurb` use-case, shard count should be related to the total number of cores on the workers. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. We typically recommend creating a high number of initial shards, e.g. **2x or 4x the number of current CPU cores**. This allows for future scaling if you add more workers and CPU cores.

However, keep in mind that for each query Citus opens one database connection per shard, and these connections are limited. Be careful to keep the shard count small enough that distributed queries won't often have to wait for a connection. Put another way, the connections needed, ``(max concurrent queries * shard count)``, should generally not exceed the total connections possible in the system, ``(number of workers * max_connections per worker)``.

.. _prod_size:

Initial Hardware Size
=====================

The size of a cluster, in terms of number of nodes and their hardware capacity, is easy to change. (Scaling on our :ref:`cloud_topic` is especially easy.) However, you still need to choose an initial size for a new cluster. Here are some tips for a reasonable initial cluster size.

Multi-Tenant SaaS Use-Case
--------------------------

For those migrating to Citus from an existing single-node database instance, we recommend choosing a cluster where the number of worker cores and RAM in total equals that of the original instance. In such scenarios we have seen 2-3x performance improvements because sharding improves resource utilization, allowing smaller indices etc.

The coordinator node needs less memory than workers, so you can choose a compute-optimized machine for running the coordinator. The number of cores required depends on your existing workload (write/read throughput).

Real-Time Analytics Use-Case
----------------------------

**Total cores:** when working data fits in RAM, you can expect a linear performance improvement on Citus proportional to the number of worker cores. To determine the right number of cores for your needs, consider the current latency for queries in your single-node database and the required latency in Citus. Divide current latency by desired latency, and round the result.

**Worker RAM:** the best case would be providing enough memory that the majority of the working set fits in memory. The type of queries your application uses affect memory requirements. You can run :code:`EXPLAIN ANALYZE` on a query to determine how much memory it requires.

.. _scaling_out_cluster:

Scaling the cluster
===================

Citus’s logical sharding based architecture allows you to scale out your cluster without any downtime. This section describes how you can add more nodes to your Citus cluster in order to improve query performance / scalability.

.. _adding_worker_node:

Add a worker
------------

Citus stores all the data for distributed tables on the worker nodes. Hence, if you want to scale out your cluster by adding more computing power, you can do so by adding a worker.

To add a new node to the cluster, you first need to add the DNS name or IP address of that node and port (on which PostgreSQL is running) in the pg_dist_node catalog table. You can do so using the :ref:`citus_add_node` UDF. Example:

.. code-block:: postgresql

   SELECT * from citus_add_node('node-name', 5432);

The new node is available for shards of new distributed tables. Existing shards will stay where they are unless redistributed, so adding a new worker may not help performance without further steps.

If your cluster has very large reference tables, they can slow down the addition of a node. In this case, consider the :ref:`replicate_reference_tables_on_activate` GUC.

.. note::

   As of Citus 8.1, workers use encrypted communication by default. A new node running version 8.1 or greater will refuse to talk with other workers who do not have SSL enabled. When adding a node to a cluster without encrypted communication, you must reconfigure the new node before creating the Citus extension.

   First, from the coordinator node check whether the other workers use SSL:

   .. code-block:: sql

      SELECT run_command_on_workers('show ssl');

   If they do not, then connect to the new node and permit it to communicate over plaintext if necessary:

   .. code-block:: sql

      ALTER SYSTEM SET citus.node_conninfo TO 'sslmode=prefer';
      SELECT pg_reload_conf();

.. _shard_rebalancing:

Rebalance Shards without Downtime
---------------------------------

.. note::

  Shard rebalancing is available in Citus Community edition, but shards are
  blocked for write access while being moved. For non-blocking reads *and*
  writes during rebalancing, try our :ref:`cloud_topic`.

If you want to move existing shards to a newly added worker, Citus provides a
:ref:`rebalance_table_shards` function to make it easier. This function will
move the shards of a given table to distribute them evenly among the workers.

The function is configurable to rebalance shards according to a number of
strategies, to best match your database workload. See the function reference to
learn which strategy to choose. Here's an example of rebalancing shards using
the default strategy:

.. code-block:: postgresql

  SELECT rebalance_table_shards();

Many products, like multi-tenant SaaS applications, cannot tolerate downtime,
and on our managed service, rebalancing is able to honor this requirement
on PostgreSQL 10 or above. This means reads and writes from the application can
continue with minimal interruption while data is being moved.

How it Works
~~~~~~~~~~~~

Our :ref:`cloud_topic`'s shard rebalancing uses PostgreSQL logical replication to move data from the old shard (called the "publisher" in replication terms) to the new (the "subscriber.") Logical replication allows application reads and writes to continue uninterrupted while copying shard data. Citus puts a brief write-lock on a shard only during the time it takes to update metadata to promote the subscriber shard as active.

As the PostgreSQL docs `explain <https://www.postgresql.org/docs/current/static/logical-replication-publication.html>`_, the source needs a *replica identity* configured:

  A published table must have a "replica identity" configured in
  order to be able to replicate UPDATE and DELETE operations, so
  that appropriate rows to update or delete can be identified on the
  subscriber side. By default, this is the primary key, if there is
  one. Another unique index (with certain additional requirements) can
  also be set to be the replica identity.

In other words, if your distributed table has a primary key defined then it's ready for shard rebalancing with no extra work. However, if it doesn't have a primary key or an explicitly defined replica identity, then attempting to rebalance it will cause an error. For instance:

.. code-block:: sql

  -- creating the following table without REPLICA IDENTITY or PRIMARY KEY
  CREATE TABLE test_table (key int not null, value text not null);
  SELECT create_distributed_table('test_table', 'key');

  -- add a new worker node to simulate need for
  -- shard rebalancing
  
  -- running shard rebalancer with default behavior
  SELECT rebalance_table_shards('test_table');

  /*
  NOTICE:  Moving shard 102040 from localhost:9701 to localhost:9700 ...
  ERROR: cannot use logical replication to transfer shards of the
    relation test_table since it doesn't have a REPLICA IDENTITY or
    PRIMARY KEY
  DETAIL:  UPDATE and DELETE commands on the shard will error out during
    logical replication unless there is a REPLICA IDENTIY or PRIMARY KEY.
  HINT:  If you wish to continue without a replica identity set the
    shard_transfer_mode to 'force_logical' or 'block_writes'.
  */

Here's how to fix this error.

**First, does the table have a unique index?**

If the table to be replicated already has a unique index which includes the distribution column, then choose that index as a replica identity:

.. code-block:: sql

  -- supposing my_table has unique index my_table_idx
  -- which includes distribution column

  ALTER TABLE my_table REPLICA IDENTITY
    USING INDEX my_table_idx;

.. note::

  While ``REPLICA IDENTITY USING INDEX`` is fine, we recommend **against** adding ``REPLICA IDENTITY FULL`` to a table. This setting would result in each update/delete doing a full-table-scan on the subscriber side to find the tuple with those rows. In our testing we’ve found this to result in worse performance than even solution four below.

**Otherwise, can you add a primary key?**

Add a primary key to the table. If the desired key happens to be the distribution column, then it's quite easy, just add the constraint. Otherwise, a primary key with a non-distribution column must be composite and contain the distribution column too.

**Unwilling to add primary key or unique index?**

If the distributed table doesn't have a primary key or replica identity, and adding one is unclear or undesirable, you can still force the use of logical replication on PostgreSQL 10 or above. It's OK to do this on a table which receives only reads and inserts (no deletes or updates). Include the optional ``shard_transfer_mode`` argument of ``rebalance_table_shards``:

.. code-block:: sql

  SELECT rebalance_table_shards(
    'test_table',
    shard_transfer_mode => 'force_logical'
  );

In this situation if an application does attempt an update or delete during replication, then the request will merely return an error. Deletes and writes will become possible again after replication is complete.

**What about PostgreSQL 9.x?**

On PostgreSQL 9.x and lower, logical replication is not supported. In this case we must fall back to a less efficient solution: locking a shard for writes as we copy it to its new location. Unlike logical replication, this approach introduces downtime for write statements (although read queries continue unaffected).

To choose this replication mode, use the ``shard_transfer_mode`` parameter again. Here is how to block writes and use the COPY command for replication:

.. code-block:: sql

  SELECT rebalance_table_shards(
    'test_table',
    shard_transfer_mode => 'block_writes'
  );

Adding a coordinator
----------------------

The Citus coordinator only stores metadata about the table shards and does not store any data. This means that all the computation is pushed down to the workers and the coordinator does only final aggregations on the result of the workers. Therefore, it is not very likely that the coordinator becomes a bottleneck for read performance. Also, it is easy to boost up the coordinator by shifting to a more powerful machine.

However, in some write heavy use cases where the coordinator becomes a performance bottleneck, users can add another coordinator. As the metadata tables are small (typically a few MBs in size), it is possible to copy over the metadata onto another node and sync it regularly. Once this is done, users can send their queries to any coordinator and scale out performance. If your setup requires you to use multiple coordinators, please `contact us <https://www.citusdata.com/about/contact_us>`_.

.. _dealing_with_node_failures:

Dealing With Node Failures
==========================

In this subsection, we discuss how you can deal with node failures without incurring any downtime on your Citus cluster.

.. _worker_node_failures:

Worker Node Failures
--------------------

Citus uses PostgreSQL streaming replication, allowing it to tolerate worker-node failures. This option  replicates entire worker nodes by continuously streaming their WAL records to a standby. You can configure streaming replication on-premise yourself by consulting the `PostgreSQL replication documentation <https://www.postgresql.org/docs/current/static/warm-standby.html#STREAMING-REPLICATION>`_ or use our :ref:`cloud_topic` which is pre-configured for replication and high-availability.

.. _coordinator_node_failures:

Coordinator Node Failures
-------------------------

The Citus coordinator maintains metadata tables to track all of the cluster nodes and the locations of the database shards on those nodes. The metadata tables are small (typically a few MBs in size) and do not change very often. This means that they can be replicated and quickly restored if the node ever experiences a failure. There are several options on how users can deal with coordinator failures.

1. **Use PostgreSQL streaming replication:** You can use PostgreSQL's streaming
   replication feature to create a hot standby of the coordinator. Then, if the
   primary coordinator node fails, the standby can be promoted to the primary
   automatically to serve queries to your cluster. For details on setting this
   up, please refer to the `PostgreSQL wiki
   <https://wiki.postgresql.org/wiki/Streaming_Replication>`_.

2. **Use backup tools:** Since the metadata tables are small, users can use EBS
   volumes, or `PostgreSQL backup tools
   <https://www.postgresql.org/docs/current/static/backup.html>`_ to backup the
   metadata. Then, they can easily copy over that metadata to new nodes to
   resume operation.

.. _tenant_isolation:

Tenant Isolation
================

.. note::

  Tenant isolation is a feature of our :ref:`cloud_topic` only.

Citus places table rows into worker shards based on the hashed value of the rows' distribution column. Multiple distribution column values often fall into the same shard. In the Citus multi-tenant use case this means that tenants often share shards.

However, sharing shards can cause resource contention when tenants differ drastically in size. This is a common situation for systems with a large number of tenants -- we have observed that the size of tenant data tend to follow a Zipfian distribution as the number of tenants increases. This means there are a few very large tenants, and many smaller ones. To improve resource allocation and make guarantees of tenant QoS it is worthwhile to move large tenants to dedicated nodes.

The Citus :ref:`cloud_topic` provides the tools to isolate a tenant on a specific node. This happens in two phases: 1) isolating the tenant's data to a new dedicated shard, then 2) moving the shard to the desired node. To understand the process it helps to know precisely how rows of data are assigned to shards.

Every shard is marked in Citus metadata with the range of hashed values it contains (more info in the reference for :ref:`pg_dist_shard <pg_dist_shard>`). The Citus UDF :code:`isolate_tenant_to_new_shard(table_name, tenant_id)` moves a tenant into a dedicated shard in three steps:

1. Creates a new shard for :code:`table_name` which (a) includes rows whose distribution column has value :code:`tenant_id` and (b) excludes all other rows.
2. Moves the relevant rows from their current shard to the new shard.
3. Splits the old shard into two with hash ranges that abut the excision above and below.

Furthermore, the UDF takes a :code:`CASCADE` option which isolates the tenant rows of not just :code:`table_name` but of all tables :ref:`co-located <colocation>` with it. Here is an example:

.. code-block:: postgresql

  -- This query creates an isolated shard for the given tenant_id and
  -- returns the new shard id.

  -- General form:

  SELECT isolate_tenant_to_new_shard('table_name', tenant_id);

  -- Specific example:

  SELECT isolate_tenant_to_new_shard('lineitem', 135);

  -- If the given table has co-located tables, the query above errors out and
  -- advises to use the CASCADE option

  SELECT isolate_tenant_to_new_shard('lineitem', 135, 'CASCADE');

Output:

::

  ┌─────────────────────────────┐
  │ isolate_tenant_to_new_shard │
  ├─────────────────────────────┤
  │                      102240 │
  └─────────────────────────────┘

The new shard(s) are created on the same node as the shard(s) from which the tenant was removed. For true hardware isolation they can be moved to a separate node in the Citus cluster. As mentioned, the :code:`isolate_tenant_to_new_shard` function returns the newly created shard id, and this id can be used to move the shard:

.. code-block:: postgresql

  -- find the node currently holding the new shard
  SELECT nodename, nodeport
    FROM citus_shards
   WHERE shardid = 102240;

  -- list the available worker nodes that could hold the shard
  SELECT * FROM master_get_active_worker_nodes();

  -- move the shard to your choice of worker
  -- (it will also move any shards created with the CASCADE option)
  SELECT citus_move_shard_placement(
    102240,
    'source_host', source_port,
    'dest_host', dest_port);

Note that :code:`citus_move_shard_placement` will also move any shards which are co-located with the specified one, to preserve their co-location.

Viewing Query Statistics
========================

.. note::

  The citus_stat_statements view is a feature of our :ref:`cloud_topic` only.

When administering a Citus cluster it's useful to know what queries users are running, which nodes are involved, and which execution method Citus is using for each query. Citus records query statistics in a metadata view called :ref:`citus_stat_statements <citus_stat_statements>`, named analogously to Postgres' `pg_stat_statments <https://www.postgresql.org/docs/current/static/pgstatstatements.html>`_. Whereas pg_stat_statements stores info about query duration and I/O, citus_stat_statements stores info about Citus execution methods and shard partition keys (when applicable).

Citus requires the ``pg_stat_statements`` extension to be installed in order to track query statistics. On our :ref:`cloud_topic` this extension will be pre-activated, but on a self-hosted Postgres instance you must load the extension in postgresql.conf via ``shared_preload_libraries``, then create the extension in SQL:

.. code-block:: postgresql

  CREATE EXTENSION pg_stat_statements;

Let's see how this works. Assume we have a table called ``foo`` that is hash-distributed by its ``id`` column.

.. code-block:: postgresql

  -- create and populate distributed table
  create table foo ( id int );
  select create_distributed_table('foo', 'id');

  insert into foo select generate_series(1,100);

We'll run two more queries, and ``citus_stat_statements`` will show how Citus chooses to execute them.

.. code-block:: postgresql

  -- counting all rows executes on all nodes, and sums
  -- the results on the coordinator
  SELECT count(*) FROM foo;

  -- specifying a row by the distribution column routes
  -- execution to an individual node
  SELECT * FROM foo WHERE id = 42;

To find how these queries were executed, ask the stats table:

.. code-block:: postgresql

  SELECT * FROM citus_stat_statements;

Results:

::

  -[ RECORD 1 ]-+----------------------------------------------
  queryid       | -6844578505338488014
  userid        | 10
  dbid          | 13340
  query         | SELECT count(*) FROM foo;
  executor      | adaptive
  partition_key |
  calls         | 1
  -[ RECORD 2 ]-+----------------------------------------------
  queryid       | 185453597994293667
  userid        | 10
  dbid          | 13340
  query         | insert into foo select generate_series($1,$2)
  executor      | insert-select
  partition_key |
  calls         | 1
  -[ RECORD 3 ]-+----------------------------------------------
  queryid       | 1301170733886649828
  userid        | 10
  dbid          | 13340
  query         | SELECT * FROM foo WHERE id = $1
  executor      | adaptive
  partition_key | 42
  calls         | 1

We can see that Citus uses the adaptive executor most commonly to run queries. This executor fragments the query into constituent queries to run on relevant nodes, and combines the results on the coordinator node. In the case of the second query (filtering by the distribution column ``id = $1``), Citus determined that it needed the data from just one node. Lastly, we can see that the ``insert into foo select…`` statement ran with the insert-select executor which provides flexibility to run these kind of queries.

So far the information in this view doesn't give us anything we couldn't already learn by running the ``EXPLAIN`` command for a given query. However, in addition to getting information about individual queries, the ``citus_stat_statements`` view allows us to answer questions such as "what percentage of queries in the cluster are scoped to a single tenant?"

.. code-block:: postgresql

  SELECT sum(calls),
         partition_key IS NOT NULL AS single_tenant
  FROM citus_stat_statements
  GROUP BY 2;

::

  .
   sum | single_tenant
  -----+---------------
     2 | f
     1 | t

In a multi-tenant database, for instance, we would expect the vast majority of queries to be single tenant. Seeing too many multi-tenant queries may indicate that queries do not have the proper filters to match a tenant, and are using unnecessary resources.

We can also find which partition_ids are the most frequent targets. In a multi-tenant application these would be the busiest tenants.

.. code-block:: sql

  SELECT partition_key, sum(calls) as total_queries
  FROM citus_stat_statements
  WHERE coalesce(partition_key, '') <> ''
  GROUP BY partition_key
  ORDER BY total_queries desc
  LIMIT 10;

::

  ┌───────────────┬───────────────┐
  │ partition_key │ total_queries │
  ├───────────────┼───────────────┤
  │ 42            │             1 │
  └───────────────┴───────────────┘

Statistics Expiration
---------------------

The pg_stat_statements view limits the number of statements it tracks, and the duration of its records. Because citus_stat_statements tracks a strict subset of the queries in pg_stat_statements, a choice of equal limits for the two views would cause a mismatch in their data retention. Mismatched records can cause joins between the views to behave unpredictably.

There are three ways to help synchronize the views, and all three can be used together.

1. Have the maintenance daemon periodically sync the citus and pg stats. The GUC ``citus.stat_statements_purge_interval`` sets time in seconds for the sync. A value of 0 disables periodic syncs.
2. Adjust the number of entries in citus_stat_statements. The ``citus.stat_statements_max`` GUC removes old entries when new ones cross the threshold. The default value is 50K, and the highest allowable value is 10M. Note that each entry costs about 140 bytes in shared memory so set the value wisely.
3. Increase ``pg_stat_statements.max``. Its default value is 5000, and could be increased to 10K, 20K or even 50K without much overhead. This is most beneficial when there is more local (i.e. coordinator) query workload.

.. note::

   Changing ``pg_stat_statements.max`` or ``citus.stat_statements_max`` requires restarting the PostgreSQL service. Changing ``citus.stat_statements_purge_interval``, on the other hand, will come into effect with a call to `pg_reload_conf() <https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL>`_.

Resource Conservation
=====================

Limiting Long-Running Queries
-----------------------------

Long running queries can hold locks, queue up WAL, or just consume a lot of system resources, so in a production environment it's good to prevent them from running too long. You can set the `statement_timeout <https://www.postgresql.org/docs/current/static/runtime-config-client.html#GUC-STATEMENT-TIMEOUT>`_ parameter on the coordinator and workers to cancel queries that run too long.

.. code-block:: postgres

   -- limit queries to five minutes
   ALTER DATABASE citus
     SET statement_timeout TO 300000;
   SELECT run_command_on_workers($cmd$
     ALTER DATABASE citus
       SET statement_timeout TO 300000;
   $cmd$);

The timeout is specified in milliseconds.

To customize the timeout per query, use ``SET LOCAL`` in a transaction:

.. code-block:: postgres

   BEGIN;
   -- this limit applies to just the current transaction
   SET LOCAL statement_timeout TO 300000;

   -- ...
   COMMIT;

Security
========

Connection Management
---------------------

.. note::

   Since Citus version 8.1.0 (released 2018-12-17) the traffic between the different nodes in the cluster is encrypted for NEW installations. This is done by using TLS with self-signed certificates. This means that this **does not protect against Man-In-The-Middle attacks.** This only protects against passive eavesdropping on the network.

   Clusters originally created with a Citus version before 8.1.0 do not have any network encryption enabled between nodes (even if upgraded later). To set up self-signed TLS on on this type of installation follow the steps in `official postgres documentation <https://www.postgresql.org/docs/current/ssl-tcp.html#SSL-CERTIFICATE-CREATION>`_ together with the citus specific settings described here, i.e. changing ``citus.node_conninfo`` to ``sslmode=require``. This setup should be done on coordinator and workers.

When Citus nodes communicate with one another they consult a GUC for connection parameters and, in our :ref:`cloud_topic`, a table with connection credentials. This gives the database administrator flexibility to adjust parameters for security and efficiency.

To set non-sensitive libpq connection parameters to be used for all node connections, update the ``citus.node_conninfo`` GUC:

.. code-block:: postgresql

  -- key=value pairs separated by spaces.
  -- For example, ssl options:

  ALTER SYSTEM SET citus.node_conninfo =
    'sslrootcert=/path/to/citus-ca.crt sslcrl=/path/to/citus-ca.crl sslmode=verify-full';

There is a whitelist of parameters that the GUC accepts, see the :ref:`node_conninfo <node_conninfo>` reference for details. As of Citus 8.1, the default value for node_conninfo is ``sslmode=require``, which prevents unencrypted communication between nodes. If your cluster was originally created before Citus 8.1 the value will be ``sslmode=prefer``. After setting up self-signed certificates on all nodes it's recommended to change this setting to ``sslmode=require``.

After changing this setting it is important to reload the postgres configuration. Even though the changed setting might be visible in all sessions, the setting is only consulted by Citus when new connections are established. When a reload signal is received, Citus marks all existing connections to be closed which causes a reconnect after running transactions have been completed.

.. code-block:: postgresql

  SELECT pg_reload_conf();

.. warning:: 

   Citus versions before 9.2.4 require a restart for existing connections to be closed.

   For these versions a reload of the configuration does not trigger connection ending and subsequent reconnecting. Instead the server should be restarted to enforce all connections to use the new settings.

.. code-block:: postgresql

  -- only superusers can access this table

  -- add a password for user jdoe
  INSERT INTO pg_dist_authinfo
    (nodeid, rolename, authinfo)
  VALUES
    (123, 'jdoe', 'password=abc123');

After this INSERT, any query needing to connect to node 123 as the user jdoe will use the supplied password. The documentation for :ref:`pg_dist_authinfo <pg_dist_authinfo>` has more info.

.. code-block:: postgresql

  -- update user jdoe to use certificate authentication
  UPDATE pg_dist_authinfo
  SET authinfo = 'sslcert=/path/to/user.crt sslkey=/path/to/user.key'
  WHERE nodeid = 123 AND rolename = 'jdoe';

This changes the user from using a password to use a certificate and keyfile while connecting to node 123 instead. Make sure the user certificate is signed by a certificate that is trusted by the worker you are connecting to and authentication settings on the worker allow for certificate based authentication. Full documentation on how to use client certificates can be found in `the postgres libpq documentation <https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-CLIENTCERT>`_.

Changing ``pg_dist_authinfo`` does not force any existing connection to reconnect.

Setup Certificate Authority signed certificates
-----------------------------------------------

This section assumes you have a trusted Certificate Authority that can issue server certificates to you for all nodes in your cluster. It is recommended to work with the security department in your organization to prevent key material from being handled incorrectly. This guide covers only Citus specific configuration that needs to be applied, not best practices for PKI management.

For all nodes in the cluster you need to get a valid certificate signed by the *same Certificate Authority*. The following **machine specific** files are assumed to be available on every machine:

* ``/path/to/server.key``: Server Private Key
* ``/path/to/server.crt``: Server Certificate or Certificate Chain for Server Key, signed by trusted Certificate Authority.

Next to these machine specific files you need these cluster or CA wide files available:

* ``/path/to/ca.crt``: Certificate of the Certificate Authority
* ``/path/to/ca.crl``: Certificate Revocation List of the Certificate Authority

.. note::

   The Certificate Revocation List is likely to change over time. Work with your security department to set up a mechanism to update the revocation list on to all nodes in the cluster in a timely manner. A reload of every node in the cluster is required after the revocation list has been updated.

Once all files are in place on the nodes, the following settings need to be configured in the Postgres configuration file:

.. code-block:: ini

   # the following settings allow the postgres server to enable ssl, and
   # configure the server to present the certificate to clients when
   # connecting over tls/ssl
   ssl = on
   ssl_key_file = '/path/to/server.key'
   ssl_cert_file = '/path/to/server.crt'

   # this will tell citus to verify the certificate of the server it is connecting to 
   citus.node_conninfo = 'sslmode=verify-full sslrootcert=/path/to/ca.crt sslcrl=/path/to/ca.crl'

After changing, either restart the database or reload the configuration to apply these changes. A restart is required if a Citus version below 9.2.4 is used. Also, adjusting :ref:`local_hostname` may be required for proper functioning with ``sslmode=verify-full``.

Depending on the policy of the Certificate Authority used you might need or want to change ``sslmode=verify-full`` in ``citus.node_conninfo`` to ``sslmode=verify-ca``. For the difference between the two settings please consult `the official postgres documentation <https://www.postgresql.org/docs/current/libpq-ssl.html#LIBPQ-SSL-SSLMODE-STATEMENTS>`_.

Lastly, to prevent any user from connecting via an un-encrypted connection, changes need to be made to ``pg_hba.conf``. Many Postgres installations will have entries allowing ``host`` connections which allow SSL/TLS connections as well as plain TCP connections. By replacing all ``host`` entries with ``hostssl`` entries, only encrypted connections will be allowed to authenticate to Postgres. For full documentation on these settings take a look at `the pg_hba.conf file <https://www.postgresql.org/docs/current/auth-pg-hba-conf.html>`_ documentation on the official Postgres documentation.

.. note::

   When a trusted Certificate Authority is not available, one can create their own via a self-signed root certificate. This is non-trivial and the developer or operator should seek guidance from their security team when doing so.

To verify the connections from the coordinator to the workers are encrypted you can run the following query. It will show the SSL/TLS version used to encrypt the connection that the coordinator uses to talk to the worker:

.. code-block:: postgresql

  SELECT run_command_on_workers($$
    SELECT version FROM pg_stat_ssl WHERE pid = pg_backend_pid()
  $$);

::
  
  ┌────────────────────────────┐
  │   run_command_on_workers   │
  ├────────────────────────────┤
  │ (localhost,9701,t,TLSv1.2) │
  │ (localhost,9702,t,TLSv1.2) │
  └────────────────────────────┘
  (2 rows)

.. _worker_security:

Increasing Worker Security
--------------------------

For your convenience getting started, our multi-node installation instructions direct you to set up the :code:`pg_hba.conf` on the workers with its `authentication method <https://www.postgresql.org/docs/current/static/auth-methods.html>`_ set to "trust" for local network connections. However, you might desire more security.

To require that all connections supply a hashed password, update the PostgreSQL :code:`pg_hba.conf` on every worker node with something like this:

.. code-block:: bash

  # Require password access and a ssl/tls connection to nodes in the local
  # network. The following ranges correspond to 24, 20, and 16-bit blocks
  # in Private IPv4 address spaces.
  hostssl    all             all             10.0.0.0/8              md5

  # Require passwords and ssl/tls connections when the host connects to
  # itself as well.
  hostssl    all             all             127.0.0.1/32            md5
  hostssl    all             all             ::1/128                 md5

The coordinator node needs to know roles' passwords in order to communicate with the workers. Our :ref:`cloud_topic` keeps track of that kind of information for you. However, in Citus Community Edition the authentication information has to be maintained in a `.pgpass <https://www.postgresql.org/docs/current/static/libpq-pgpass.html>`_ file. Edit .pgpass in the postgres user's home directory, with a line for each combination of worker address and role:

::

  hostname:port:database:username:password

Sometimes workers need to connect to one another, such as during :ref:`repartition joins <repartition_joins>`. Thus each worker node requires a copy of the .pgpass file as well.

.. _rls:

Row-Level Security
------------------

.. note::

  Row-level security support is a part of our :ref:`cloud_topic` only.

PostgreSQL `row-level security <https://www.postgresql.org/docs/current/static/ddl-rowsecurity.html>`_ policies restrict, on a per-user basis, which rows can be returned by normal queries or inserted, updated, or deleted by data modification commands. This can be especially useful in a multi-tenant Citus cluster because it allows individual tenants to have full SQL access to the database while hiding each tenant's information from other tenants.

We can implement the separation of tenant data by using a naming convention for database roles that ties into table row-level security policies. We'll assign each tenant a database role in a numbered sequence: ``tenant_1``, ``tenant_2``, etc. Tenants will connect to Citus using these separate roles. Row-level security policies can compare the role name to values in the ``tenant_id`` distribution column to decide whether to allow access.

Here is how to apply the approach on a simplified events table distributed by ``tenant_id``. First create the roles ``tenant_1`` and ``tenant_2``. Then run the following as an administrator:

.. code-block:: sql

  CREATE TABLE events(
    tenant_id int,
    id int,
    type text
  );

  SELECT create_distributed_table('events','tenant_id');

  INSERT INTO events VALUES (1,1,'foo'), (2,2,'bar');

  -- assumes that roles tenant_1 and tenant_2 exist
  GRANT select, update, insert, delete
    ON events TO tenant_1, tenant_2;

As it stands, anyone with select permissions for this table can see both rows. Users from either tenant can see and update the row of the other tenant. We can solve this with row-level table security policies.

Each policy consists of two clauses: USING and WITH CHECK. When a user tries to read or write rows, the database evaluates each row against these clauses. Existing table rows are checked against the expression specified in USING, while new rows that would be created via INSERT or UPDATE are checked against the expression specified in WITH CHECK.

.. code-block:: postgresql

  -- first a policy for the system admin "citus" user
  CREATE POLICY admin_all ON events
    TO citus           -- apply to this role
    USING (true)       -- read any existing row
    WITH CHECK (true); -- insert or update any row

  -- next a policy which allows role "tenant_<n>" to
  -- access rows where tenant_id = <n>
  CREATE POLICY user_mod ON events
    USING (current_user = 'tenant_' || tenant_id::text);
    -- lack of CHECK means same condition as USING

  -- enforce the policies
  ALTER TABLE events ENABLE ROW LEVEL SECURITY;

Now roles ``tenant_1`` and ``tenant_2`` get different results for their queries:

**Connected as tenant_1:**

.. code-block:: sql

  SELECT * FROM events;

::

  ┌───────────┬────┬──────┐
  │ tenant_id │ id │ type │
  ├───────────┼────┼──────┤
  │         1 │  1 │ foo  │
  └───────────┴────┴──────┘

**Connected as tenant_2:**

.. code-block:: sql

  SELECT * FROM events;

::

  ┌───────────┬────┬──────┐
  │ tenant_id │ id │ type │
  ├───────────┼────┼──────┤
  │         2 │  2 │ bar  │
  └───────────┴────┴──────┘

.. code-block:: sql

  INSERT INTO events VALUES (3,3,'surprise');
  /*
  ERROR:  new row violates row-level security policy for table "events_102055"
  */

.. _sql_extensions:

PostgreSQL extensions
=====================

Citus provides distributed functionality by extending PostgreSQL using the hook and extension APIs. This allows users to benefit from the features that come with the rich PostgreSQL ecosystem. These features include, but aren’t limited to, support for a wide range of `data types <http://www.postgresql.org/docs/current/static/datatype.html>`_ (including semi-structured data types like jsonb and hstore), `operators and functions <http://www.postgresql.org/docs/current/static/functions.html>`_, full text search, and other extensions such as `PostGIS <http://postgis.net/>`_ and `HyperLogLog <https://github.com/aggregateknowledge/postgresql-hll>`_. Further, proper use of the extension APIs enable compatibility with standard PostgreSQL tools such as `pgAdmin <http://www.pgadmin.org/>`_  and `pg_upgrade <http://www.postgresql.org/docs/current/static/pgupgrade.html>`_.

As Citus is an extension which can be installed on any PostgreSQL instance, you can directly use other extensions such as hstore, hll, or PostGIS with Citus. However, there is one thing to keep in mind. While including other extensions in shared_preload_libraries, you should make sure that Citus is the first extension.

.. note::
  Sometimes, there might be a few features of the extension that may not be supported out of the box. For example, a few aggregates in an extension may need to be modified a bit to be parallelized across multiple nodes. Please `contact us <https://www.citusdata.com/about/contact_us>`_ if some feature from your favourite extension does not work as expected with Citus.

In addition to our core Citus extension, we also maintain several others:

* `cstore_fdw <https://github.com/citusdata/cstore_fdw>`_ - Columnar store for analytics. The columnar nature delivers performance by reading only relevant data from disk, and it may compress data 6x-10x to reduce space requirements for data archival.
* `pg_cron <https://github.com/citusdata/pg_cron>`_ - Run periodic jobs directly from the database.
* `postgresql-topn <https://github.com/citusdata/postgresql-topn>`_ - Returns the top values in a database according to some criteria. Uses an approximation algorithm to provide fast results with modest compute and memory resources.
* `postgresql-hll <https://github.com/citusdata/postgresql-hll>`_ - HyperLogLog data structure as a native data type. It's a fixed-size, set-like structure used for distinct value counting with tunable precision.

.. _create_db:

Creating a New Database
=======================

Each PostgreSQL server can hold `multiple databases <https://www.postgresql.org/docs/current/static/manage-ag-overview.html>`_. However, new databases do not inherit the extensions of any others; all desired extensions must be added afresh. To run Citus on a new database, you'll need to create the database on the coordinator and workers, create the Citus extension within that database, and register the workers in the coordinator database.

Connect to each of the worker nodes and run:

.. code-block:: psql

  -- on every worker node

  CREATE DATABASE newbie;
  \c newbie
  CREATE EXTENSION citus;

Then, on the coordinator:

.. code-block:: psql

  CREATE DATABASE newbie;
  \c newbie
  CREATE EXTENSION citus;

  SELECT * from citus_add_node('node-name', 5432);
  SELECT * from citus_add_node('node-name2', 5432);
  -- ... for all of them

Now the new database will be operating as another Citus cluster.
