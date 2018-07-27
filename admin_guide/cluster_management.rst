.. _cluster_management:

Cluster Management
##################

In this section, we discuss how you can add or remove nodes from your Citus cluster and how you can deal with node failures.

.. note::
  To make moving shards across nodes or re-replicating shards on failed nodes easier, Citus Enterprise comes with a shard rebalancer extension. We discuss briefly about the functions provided by the shard rebalancer as and when relevant in the sections below. You can learn more about these functions, their arguments and usage, in the :ref:`cluster_management_functions` reference section.

.. _production_sizing:

Choosing Cluster Size
=====================

This section explores configuration settings for running a cluster in production.

.. _prod_shard_count:

Shard Count
-----------

The number of nodes in a cluster is easy to change (see :ref:`scaling_out_cluster`), but the number of shards to distribute among those nodes is more difficult to change after cluster creation. Choosing the shard count for each distributed table is a balance between the flexibility of having more shards, and the overhead for query planning and execution across them.

Multi-Tenant SaaS Use-Case
~~~~~~~~~~~~~~~~~~~~~~~~~~

The optimal choice varies depending on your access patterns for the data. For instance, in the :ref:`mt_blurb` use-case we recommend choosing between **32 - 128 shards**.  For smaller workloads say <100GB, you could start with 32 shards and for larger workloads you could choose 64 or 128. This means that you have the leeway to scale from 32 to 128 worker machines.

Real-Time Analytics Use-Case
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the :ref:`rt_blurb` use-case, shard count should be related to the total number of cores on the workers. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. We typically recommend creating a high number of initial shards, e.g. **2x or 4x the number of current CPU cores**. This allows for future scaling if you add more workers and CPU cores.

.. _prod_size:

Initial Hardware Size
=====================

The size of a cluster, in terms of number of nodes and their hardware capacity, is easy to change. (:ref:`Scaling <cloud_scaling>` on Citus Cloud is especially easy.) However you still need to choose an initial size for a new cluster. Here are some tips for a reasonable initial cluster size.

Multi-Tenant SaaS Use-Case
--------------------------

For those migrating to Citus from an existing single-node database instance, we recommend choosing a cluster where the number of worker cores and RAM in total equals that of the original instance. In such scenarios we have seen 2-3x performance improvements because sharding improves resource utilization, allowing smaller indices etc.

The coordinator node needs less memory than workers, so you can choose a compute-optimized machine for running the coordinator. The number of cores required depends on your existing workload (write/read throughput). By default in Citus Cloud the workers use Amazon EC2 instance type R4S, and the coordinator uses C4S.

Real-Time Analytics Use-Case
----------------------------

**Total cores:** when working data fits in RAM, you can expect a linear performance improvement on Citus proportional to the number of worker cores. To determine the right number of cores for your needs, consider the current latency for queries in your single-node database and the required latency in Citus. Divide current latency by desired latency, and round the result.

**Worker RAM:** the best case would be providing enough memory that the majority of the working set fits in memory. The type of queries your application uses affect memory requirements. You can run :code:`EXPLAIN ANALYZE` on a query to determine how much memory it requires.

.. _scaling_out_cluster:

Scaling the cluster
===================

Citus’s logical sharding based architecture allows you to scale out your cluster without any down time. This section describes how you can add more nodes to your Citus cluster in order to improve query performance / scalability.

.. _adding_worker_node:

Add a worker
------------

Citus stores all the data for distributed tables on the worker nodes. Hence, if you want to scale out your cluster by adding more computing power, you can do so by adding a worker.

To add a new node to the cluster, you first need to add the DNS name or IP address of that node and port (on which PostgreSQL is running) in the pg_dist_node catalog table. You can do so using the :ref:`master_add_node` UDF. Example:

.. code-block:: postgresql

   SELECT * from master_add_node('node-name', 5432);

The new node is available for shards of new distributed tables. Existing shards will stay where they are unless redistributed, so adding a new worker may not help performance without further steps.

.. _shard_rebalancing:

Rebalance Shards without Downtime
---------------------------------

If you want to move existing shards to a newly added worker, Citus Enterprise and Citus Cloud provide a :ref:`rebalance_table_shards` function to make it easier. This function will move the shards of a given table to distribute them evenly among the workers.

.. code-block:: postgresql

  SELECT rebalance_table_shards('github_events');

Many products, like multi-tenant SaaS applications, cannot tolerate downtime, and Citus rebalancing is able to honor this requirement on PostgreSQL 10 or above. This means reads and writes from the application can continue with minimal interruption while data is being moved.

How it Works
~~~~~~~~~~~~

Citus' shard rebalancing uses PostgreSQL logical replication to move data from the old shard (called the "publisher" in replication terms) to the new (the "subscriber.") Logical replication allows application reads and writes to continue uninterrupted while copying shard data. Citus puts a brief write-lock on a shard only during the time it takes to update metadata to promote the subscriber shard as active.

As the PostgreSQL docs `explain <https://www.postgresql.org/docs/current/static/logical-replication-publication.html>`_, the source needs a *replica identity* configured:

  A published table must have a "replica identity" configured in
  order to be able to replicate UPDATE and DELETE operations, so
  that appropriate rows to update or delete can be identified on the
  subscriber side. By default, this is the primary key, if there is
  one. Another unique index (with certain additional requirements) can
  also be set to be the replica identity.

In other words, if your distributed table has a primary key defined then it's ready for shard rebalancing with no extra work. However if it doesn't have a primary key or an explicitly defined replica identity, then attempting to rebalance it will cause an error. For instance:

.. code-block:: sql

  -- creating the following table without REPLICA IDENTITY or PRIMARY KEY
  CREATE TABLE test_table (key int not null, value text not null);
  SELECT create_distributed_table('test_table', 'key');

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

In this sub-section, we discuss how you can deal with node failures without incurring any downtime on your Citus cluster. We first discuss how Citus handles worker failures automatically by maintaining multiple replicas of the data. We also briefly describe how users can replicate their shards to bring them to the desired replication factor in case a node is down for a long time. Lastly, we discuss how you can setup redundancy and failure handling mechanisms for the coordinator.

.. _worker_node_failures:

Worker Node Failures
--------------------

Citus supports two modes of replication, allowing it to tolerate worker-node failures. In the first model, we use PostgreSQL's streaming replication to replicate the entire worker-node as-is. In the second model, Citus can replicate data modification statements, thus replicating shards across different worker nodes. They have different advantages depending on the workload and use-case as discussed below:

1. **PostgreSQL streaming replication.** This option is best for heavy OLTP workloads. It replicates entire worker nodes by continuously streaming their WAL records to a standby. You can configure streaming replication on-premise yourself by consulting the `PostgreSQL replication documentation <https://www.postgresql.org/docs/current/static/warm-standby.html#STREAMING-REPLICATION>`_ or use :ref:`Citus Cloud <cloud_overview>` which is pre-configured for replication and high-availability.

2. **Citus shard replication.** This option is best suited for an append-only workload. Citus replicates shards across different nodes by automatically replicating DML statements and managing consistency. If a node goes down, the co-ordinator node will continue to serve queries by routing the work to the replicas seamlessly. To enable shard replication simply set :code:`SET citus.shard_replication_factor = 2;` (or higher) before distributing data to the cluster.

.. _coordinator_node_failures:

Coordinator Node Failures
-------------------------

The Citus coordinator maintains metadata tables to track all of the cluster nodes and the locations of the database shards on those nodes. The metadata tables are small (typically a few MBs in size) and do not change very often. This means that they can be replicated and quickly restored if the node ever experiences a failure. There are several options on how users can deal with coordinator failures.

1. **Use PostgreSQL streaming replication:** You can use PostgreSQL's streaming
replication feature to create a hot standby of the coordinator. Then, if the primary
coordinator node fails, the standby can be promoted to the primary automatically to
serve queries to your cluster. For details on setting this up, please refer to the `PostgreSQL wiki <https://wiki.postgresql.org/wiki/Streaming_Replication>`_.

2. Since the metadata tables are small, users can use EBS volumes, or `PostgreSQL
backup tools <https://www.postgresql.org/docs/current/static/backup.html>`_ to backup the metadata. Then, they can easily
copy over that metadata to new nodes to resume operation.

.. _tenant_isolation:

Tenant Isolation
================

.. note::

  Tenant isolation is a feature of **Citus Enterprise Edition** and :ref:`Citus Cloud <cloud_overview>` only.

Citus places table rows into worker shards based on the hashed value of the rows' distribution column. Multiple distribution column values often fall into the same shard. In the Citus multi-tenant use case this means that tenants often share shards.

However sharing shards can cause resource contention when tenants differ drastically in size. This is a common situation for systems with a large number of tenants -- we have observed that the size of tenant data tend to follow a Zipfian distribution as the number of tenants increases. This means there are a few very large tenants, and many smaller ones. To improve resource allocation and make guarantees of tenant QoS it is worthwhile to move large tenants to dedicated nodes.

Citus Enterprise Edition and :ref:`Citus Cloud <cloud_overview>` provide the tools to isolate a tenant on a specific node. This happens in two phases: 1) isolating the tenant's data to a new dedicated shard, then 2) moving the shard to the desired node. To understand the process it helps to know precisely how rows of data are assigned to shards.

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
    FROM pg_dist_placement AS placement,
         pg_dist_node AS node
   WHERE placement.groupid = node.groupid
     AND node.noderole = 'primary'
     AND shardid = 102240;

  -- list the available worker nodes that could hold the shard
  SELECT * FROM master_get_active_worker_nodes();

  -- move the shard to your choice of worker
  -- (it will also move any shards created with the CASCADE option)
  SELECT master_move_shard_placement(
    102240,
    'source_host', source_port,
    'dest_host', dest_port);

Note that :code:`master_move_shard_placement` will also move any shards which are co-located with the specified one, to preserve their co-location.

Viewing Query Statistics
========================

.. note::

  The citus_stat_statements view is a feature of **Citus Enterprise Edition** and :ref:`Citus Cloud <cloud_overview>` only.

When administering a Citus cluster it's useful to know what queries users are running, which nodes are involved, and which execution method Citus is using for each query. Citus records query statistics in a metadata view called :ref:`citus_stat_statements <citus_stat_statements>`, named analogously to Postgres' `pg_stat_statments <https://www.postgresql.org/docs/current/static/pgstatstatements.html>`_. Whereas pg_stat_statements stores info about query duration and I/O, citus_stat_statements stores info about Citus execution methods and shard partition keys (when applicable).

Citus requires the ``pg_stat_statements`` extension to be installed in order to track query statistics. On Citus Cloud this extension will be pre-activated, but on a self-hosted Postgres instance you must load the extension in postgresql.conf via ``shared_preload_libraries``, then create the extension in SQL:

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

  ┌────────────┬────────┬───────┬───────────────────────────────────────────────┬───────────────┬───────────────┬───────┐
  │  queryid   │ userid │ dbid  │                     query                     │   executor    │ partition_key │ calls │
  ├────────────┼────────┼───────┼───────────────────────────────────────────────┼───────────────┼───────────────┼───────┤
  │ 1496051219 │  16384 │ 16385 │ select count(*) from foo;                     │ real-time     │ NULL          │     1 │
  │ 2530480378 │  16384 │ 16385 │ select * from foo where id = $1               │ router        │ 42            │     1 │
  │ 3233520930 │  16384 │ 16385 │ insert into foo select generate_series($1,$2) │ insert-select │ NULL          │     1 │
  └────────────┴────────┴───────┴───────────────────────────────────────────────┴───────────────┴───────────────┴───────┘

We can see that Citus used the real-time executor to run the count query. This executor fragments the query into constituent queries to run on each node and combines the results on the coordinator node. In the case of the second query (filtering by the distribution column ``id = $1``), Citus determined that it needed the data from just one node. Thus Citus chose the router executor to send the whole query to that node for execution. Lastly, we can see that the ``insert into foo select…`` statement ran with the insert-select executor which provides flexibility to run these kind of queries.  The insert-select executor must sometimes pull results to the coordinator and push them back down to workers.

So far the information in this view doesn't give us anything we couldn't already learn by running the ``EXPLAIN`` command for a given query. However in addition to getting information about individual queries, the ``citus_stat_statements`` view allows us to answer questions such as "what percentage of queries in the cluster are run by which executors?"

.. code-block:: postgresql

  SELECT executor, sum(calls)
  FROM citus_stat_statements
  GROUP BY executor;

::

  ┌───────────────┬─────┐
  │   executor    │ sum │
  ├───────────────┼─────┤
  │ insert-select │   1 │
  │ real-time     │   1 │
  │ router        │   1 │
  └───────────────┴─────┘

In a multi-tenant database, for instance, we would expect to see "router" for the vast majority of queries, because the queries should route to individual tenants. Seeing too many real-time queries may indicate that queries do not have the proper filters to match a tenant, and are using unnecessary resources.

We can also find which partition_ids are the most frequent targets of router execution. In a multi-tenant application these would be the busiest tenants.

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


Finally, by joining ``citus_stat_statements`` with ``pg_stat_statements`` we can gain a better view into not only how many queries use different executor types, but how much time each executor spends running queries.

.. code-block:: sql

  SELECT executor, sum(css.calls), sum(pss.total_time)
  FROM citus_stat_statements css
  JOIN pg_stat_statements pss USING (queryid)
  GROUP BY executor;

::

  ┌───────────────┬─────┬───────────┐
  │   executor    │ sum │    sum    │
  ├───────────────┼─────┼───────────┤
  │ insert-select │   1 │ 18.393312 │
  │ real-time     │   1 │  3.537155 │
  │ router        │   1 │  0.392590 │
  └───────────────┴─────┴───────────┘

Security
========

Connection Management
---------------------

When Citus nodes communicate with one another they consult a GUC for connection parameters and, in the Enterprise Edition of Citus, a table with connection credentials. This gives the database administrator flexibility to adjust parameters for security and efficiency.

To set non-sensitive libpq connection parameters to be used for all node connections, update the ``citus.node_conninfo`` GUC:

.. code-block:: postgresql

  -- key=value pairs separated by spaces.
  -- For example, ssl options:

  ALTER DATABASE foo
  SET citus.node_conninfo =
    'sslrootcert=/path/to/citus.crt sslmode=verify-full';

There is a whitelist of parameters that the GUC accepts. See the :ref:`node_conninfo <node_conninfo>` reference for details.

Citus Enterprise Edition includes an extra table used to set sensitive connection credentials. This is fully configurable per host/user. It's easier than managing ``.pgpass`` files through the cluster and additionally supports certificate authentication.

.. code-block:: postgresql

  -- only superusers can access this table

  INSERT INTO pg_dist_authinfo
    (nodeid, rolename, authinfo)
  VALUES
    (123, 'jdoe', 'password=abc123');

After this INSERT, any query needing to connect to node 123 as the user jdoe will use the supplied password. The documentation for :ref:`pg_dist_authinfo <pg_dist_authinfo>` has more info.

.. _worker_security:

Increasing Worker Security
--------------------------

For your convenience getting started, our multi-node installation instructions direct you to set up the :code:`pg_hba.conf` on the workers with its `authentication method <https://www.postgresql.org/docs/current/static/auth-methods.html>`_ set to "trust" for local network connections. However you might desire more security.

To require that all connections supply a hashed password, update the PostgreSQL :code:`pg_hba.conf` on every worker node with something like this:

.. code-block:: bash

  # Require password access to nodes in the local network. The following ranges
  # correspond to 24, 20, and 16-bit blocks in Private IPv4 address spaces.
  host    all             all             10.0.0.0/8              md5

  # Require passwords when the host connects to itself as well
  host    all             all             127.0.0.1/32            md5
  host    all             all             ::1/128                 md5

The coordinator node needs to know roles' passwords in order to communicate with the workers. In Citus Enterprise the ``pg_dist_authinfo`` table can provide that information, as discussed earlier. However in Citus Community Edition the authentication information has to be maintained in a `.pgpass <https://www.postgresql.org/docs/current/static/libpq-pgpass.html>`_ file. Edit .pgpass in the postgres user's home directory, with a line for each combination of worker address and role:

.. code-block:: ini

  hostname:port:database:username:password

Sometimes workers need to connect to one another, such as during :ref:`repartition joins <repartition_joins>`. Thus each worker node requires a copy of the .pgpass file as well.

.. _rls:

Row-Level Security
------------------

.. note::

  Row-level security support is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

PostgreSQL `row-level security <https://www.postgresql.org/docs/current/static/ddl-rowsecurity.html>`_ policies restrict, on a per-user basis, which rows can be returned by normal queries or inserted, updated, or deleted by data modification commands. This can be especially useful in a multi-tenant Citus cluster because it allows individual tenants to have full SQL access to the database while hiding each tenant's information from other tenants.

We can implement the separation of tenant data by using a naming convention for database roles that ties into table row-level security policies. We'll assign each tenant a database role in a numbered sequence: ``tenant_1``, ``tenant_2``, etc. Tenants will connect to Citus using these separate roles. Row-level security policies can compare the role name to values in the ``tenant_id`` distribution column to decide whether to allow access.

Here is how to apply the approach on a simplified events table distributed by ``tenant_id``. First create the roles ``tenant_1`` and ``tenant_2`` (it's easy on Citus Cloud, see :ref:`cloud_roles`). Then run the following as an administrator:

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
  ERROR:  42501: new row violates row-level security policy for table "events_102055"
  */

.. _sql_extensions:

PostgreSQL extensions
=====================

Citus provides distributed functionality by extending PostgreSQL using the hook and extension APIs. This allows users to benefit from the features that come with the rich PostgreSQL ecosystem. These features include, but aren’t limited to, support for a wide range of `data types <http://www.postgresql.org/docs/current/static/datatype.html>`_ (including semi-structured data types like jsonb and hstore), `operators and functions <http://www.postgresql.org/docs/current/static/functions.html>`_, full text search, and other extensions such as `PostGIS <http://postgis.net/>`_ and `HyperLogLog <https://github.com/aggregateknowledge/postgresql-hll>`_. Further, proper use of the extension APIs enable compatibility with standard PostgreSQL tools such as `pgAdmin <http://www.pgadmin.org/>`_  and `pg_upgrade <http://www.postgresql.org/docs/current/static/pgupgrade.html>`_.

As Citus is an extension which can be installed on any PostgreSQL instance, you can directly use other extensions such as hstore, hll, or PostGIS with Citus. However, there are two things to keep in mind. First, while including other extensions in shared_preload_libraries, you should make sure that Citus is the first extension. Secondly, you should create the extension on both the coordinator and the workers before starting to use it.

.. note::
  Sometimes, there might be a few features of the extension that may not be supported out of the box. For example, a few aggregates in an extension may need to be modified a bit to be parallelized across multiple nodes. Please `contact us <https://www.citusdata.com/about/contact_us>`_ if some feature from your favourite extension does not work as expected with Citus.

In addition to our core Citus extension, we also maintain several others:

* `cstore_fdw <https://github.com/citusdata/cstore_fdw>`_ - Columnar store for analytics. The columnar nature delivers performance by reading only relevant data from disk, and it may compress data 6x-10x to reduce space requirements for data archival.
* `pg_cron <https://github.com/citusdata/pg_cron>`_ - Run periodic jobs directly from the database.
* `postgresql-topn <https://github.com/citusdata/postgresql-topn>`_ - Returns the top values in a database according to some criteria. Uses an approximation algorithm to provide fast results with modest compute and memory resources.
* `postgresql-hll <https://github.com/citusdata/postgresql-hll>`_ - HyperLogLog data structure as a native data type. It's a fixed-size, set-like structure used for distinct value counting with tunable precision.

.. _phone_home:

Checks For Updates and Cluster Statistics
=========================================

Unless you opt out, Citus checks if there is a newer version of itself during installation and every twenty-four hours thereafter. If a new version is available, Citus emits a notice to the database logs:

::

  a new minor release of Citus (X.Y.Z) is available

During the check for updates, Citus also sends general anonymized information about the running cluster to Citus Data company servers. This helps us understand how Citus is commonly used and thereby improve the product. As explained below, the reporting is opt-out and does **not** contain personally identifying information about schemas, tables, queries, or data.

What we Collect
---------------

1. Citus checks if there is a newer version of itself, and if so emits a notice to the database logs.
2. Citus collects and sends these statistics about your cluster:

   * Randomly generated cluster identifier
   * Number of workers
   * OS version and hardware type (output of ``uname -psr`` command)
   * Number of tables, rounded to a power of two
   * Total size of shards, rounded to a power of two
   * Whether Citus is running in Docker or natively

Because Citus is an open-source PostgreSQL extension, the statistics reporting code is available for you to audit. See `statistics_collection.c <https://github.com/citusdata/citus/blob/master/src/backend/distributed/utils/statistics_collection.c>`_.

How to Opt Out
--------------

If you wish to disable our anonymized cluster statistics gathering, set the following GUC in postgresql.conf on your coordinator node:

.. code-block:: ini

  citus.enable_statistics_collection = off

This disables all reporting and in fact all communication with Citus Data servers, including checks for whether a newer version of Citus is available.

If you have super-user SQL access you can also achieve this without needing to find and edit the configuration file. Just execute the following statement in psql:

.. code-block:: postgresql

  ALTER SYSTEM SET citus.enable_statistics_collection = 'off';

Since Docker users won't have the chance to edit this PostgreSQL variable before running the image, we added a Docker flag to disable reports.

.. code-block:: bash

  # Docker flag prevents reports

  docker run -e DISABLE_STATS_COLLECTION=true citusdata/citus:latest
