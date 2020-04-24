.. _faq:

Frequently Asked Questions
##########################


Can I create primary keys on distributed tables?
------------------------------------------------

Currently Citus imposes primary key constraint only if the distribution column is a part of the primary key. This assures that the constraint needs to be checked only on one shard to ensure uniqueness.

How do I add nodes to an existing Citus cluster?
------------------------------------------------

On Citus Cloud it's as easy as dragging a slider in the user interface. The :ref:`scaling_out` section has instructions. In Citus Community edition you can add nodes manually by calling the :ref:`master_add_node` UDF with the hostname (or IP address) and port number of the new node.

Either way, after adding a node to an existing cluster it will not contain any data (shards). Citus will start assigning any newly created shards to this node. To rebalance existing shards from the older nodes to the new node, Citus Cloud and Enterprise edition provide a shard rebalancer utility. You can find more information in the :ref:`shard_rebalancing` section.

How does Citus handle failure of a worker node?
-----------------------------------------------

Citus supports two modes of replication, allowing it to tolerate worker-node failures. In the first model, we use PostgreSQL's streaming replication to replicate the entire worker-node as-is. In the second model, Citus can replicate data modification statements, thus replicating shards across different worker nodes. They have different advantages depending on the workload and use-case as discussed below:

1. **PostgreSQL streaming replication.** This option is best for heavy OLTP workloads. It replicates entire worker nodes by continuously streaming their WAL records to a standby. You can configure streaming replication on-premise yourself by consulting the `PostgreSQL replication documentation <https://www.postgresql.org/docs/current/static/warm-standby.html#STREAMING-REPLICATION>`_ or use :ref:`Citus Cloud <cloud_overview>` which is pre-configured for replication and high-availability.

2. **Citus shard replication.** This option is best suited for an append-only workload. Citus replicates shards across different nodes by automatically replicating DML statements and managing consistency. If a node goes down, the coordinator node will continue to serve queries by routing the work to the replicas seamlessly. To enable shard replication simply set :code:`SET citus.shard_replication_factor = 2;` (or higher) before distributing data to the cluster.

How does Citus handle failover of the coordinator node?
-------------------------------------------------------

As the Citus coordinator node is similar to a standard PostgreSQL server, regular PostgreSQL synchronous replication and failover can be used to provide higher availability of the coordinator node. Many of our customers use synchronous replication in this way to add resilience against coordinator node failure. You can find more information about handling :ref:`coordinator_node_failures`.

How do I ingest the results of a query into a distributed table?
----------------------------------------------------------------

Citus supports the `INSERT / SELECT <https://www.postgresql.org/docs/current/static/sql-insert.html>`_ syntax for copying the results of a query on a distributed table into a distributed table, when the tables are :ref:`co-located <colocation>`.

If your tables are not co-located, or you are using append distribution, there
are workarounds you can use (for eg. using COPY to copy data out and then back
into the destination table). Please contact us if your use-case demands such
ingest workflows.

Can I join distributed and non-distributed tables together in the same query?
-----------------------------------------------------------------------------

If you want to do joins between small dimension tables (regular Postgres tables) and large tables (distributed), then wrap the local table in a subquery. Citus' subquery execution logic will allow the join to work. See :ref:`join_local_dist`.

.. _unsupported:

Are there any PostgreSQL features not supported by Citus?
---------------------------------------------------------

Since Citus provides distributed functionality by extending PostgreSQL, it uses the standard PostgreSQL SQL constructs. The vast majority of queries are supported, even when they combine data across the network from multiple database nodes. This includes transactional semantics across nodes. Currently all SQL is supported except:

* Correlated subqueries
* Recursive CTEs
* Table sample
* SELECT … FOR UPDATE
* Grouping sets
* Window functions that do not include the distribution column in PARTITION BY

What's more, Citus has 100% SQL support for queries which access a single node in the database cluster. These queries are common, for instance, in multi-tenant applications where different nodes store different tenants (see :ref:`when_to_use_citus`).

Remember that -- even with this extensive SQL coverage -- data modeling can have a significant impact on query performance. See the section on :ref:`citus_query_processing` for details on how Citus executes queries.


.. _faq_choose_shard_count:

How do I choose the shard count when I hash-partition my data?
--------------------------------------------------------------

One of the choices when first distributing a table is its shard count. This setting can be set differently for each co-location group, and the optimal value depends on use-case. It is possible, but difficult, to change the count after cluster creation, so use these guidelines to choose the right size.

In the :ref:`mt_blurb` use-case we recommend choosing between 32 - 128 shards.  For smaller workloads say <100GB, you could start with 32 shards and for larger workloads you could choose 64 or 128. This means that you have the leeway to scale from 32 to 128 worker machines.

In the :ref:`rt_blurb` use-case, shard count should be related to the total number of cores on the workers. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core. We typically recommend creating a high number of initial shards, e.g. 2x or 4x the number of current CPU cores. This allows for future scaling if you add more workers and CPU cores.

To choose a shard count for a table you wish to distribute, update the :code:`citus.shard_count` variable. This affects subsequent calls to :ref:`create_distributed_table`. For example

.. code-block:: postgres

  SET citus.shard_count = 64;
  -- any tables distributed at this point will have
  -- sixty-four shards

For more guidance on this topic, see :ref:`production_sizing`.

How do I change the shard count for a hash partitioned table?
-------------------------------------------------------------

Note that it is not straightforward to change the shard count of an already distributed table. If you need to do so, please `Contact Us <https://www.citusdata.com/about/contact_us>`_. It's good to think about shard count carefully at distribution time, see :ref:`faq_choose_shard_count`.

How does citus support count(distinct) queries?
-----------------------------------------------

Citus can evaluate count(distinct) aggregates both in and across worker nodes. When aggregating on a table's distribution column, Citus can push the counting down inside worker nodes and total the results. Otherwise it can pull distinct rows to the coordinator and calculate there. If transferring data to the coordinator is too expensive, fast approximate counts are also available. More details in :ref:`count_distinct`.

In which situations are uniqueness constraints supported on distributed tables?
-------------------------------------------------------------------------------

Citus is able to enforce a primary key or uniqueness constraint only when the constrained columns contain the distribution column. In particular this means that if a single column constitutes the primary key then it has to be the distribution column as well.

This restriction allows Citus to localize a uniqueness check to a single shard and let PostgreSQL on the worker node do the check efficiently.

How do I create database roles, functions, extensions etc in a Citus cluster?
-----------------------------------------------------------------------------

Certain commands, when run on the coordinator node, do not get propagated to the workers:

* ``CREATE ROLE/USER (gets propagated in Citus Enterprise)``
* ``CREATE DATABASE``
* ``ALTER … SET SCHEMA``
* ``ALTER TABLE ALL IN TABLESPACE``
* ``CREATE FUNCTION`` (use :ref:`create_distributed_function`)
* ``CREATE TABLE`` (see :ref:`table_types`)

For the other types of objects above, create them explicitly on all nodes. Citus provides a function to execute queries across all workers:

.. code-block:: postgresql

  SELECT run_command_on_workers($cmd$
    /* the command to run */
    CREATE ROLE ...
  $cmd$);

Learn more in :ref:`manual_prop`. Also note that even after manually propagating CREATE DATABASE, Citus must still be installed there. See :ref:`create_db`.

In the future Citus will automatically propagate more kinds of objects. The advantage of automatic propagation is that Citus will automatically create a copy on any newly added worker nodes (see :ref:`pg_dist_object` for more about that.)

What if a worker node's address changes?
----------------------------------------

If the hostname or IP address of a worker changes, you need to let the coordinator know using :ref:`master_update_node`:

.. code-block:: sql

  -- update worker node metadata on the coordinator
  -- (remember to replace 'old-address' and 'new-address'
  --  with the actual values for your situation)

  select master_update_node(nodeid, 'new-address', nodeport)
    from pg_dist_node
   where nodename = 'old-address';

Until you execute this update, the coordinator will not be able to communicate with that worker for queries.

Which shard contains data for a particular tenant?
--------------------------------------------------

Citus provides UDFs and metadata tables to determine the mapping of a distribution column value to a particular shard, and the shard placement on a worker node. See :ref:`row_placements` for more details.

I forgot the distribution column of a table, how do I find it?
--------------------------------------------------------------

The Citus coordinator node metadata tables contain this information. See :ref:`finding_dist_col`.

Can I distribute a table by multiple keys?
------------------------------------------

No, you must choose a single column per table as the distribution column. A common scenario where people want to distribute by two columns is for timeseries data. However for this case we recommend using a hash distribution on a non-time column, and combining this with PostgreSQL partitioning on the time column, as described in :ref:`distributing_hash_time`.

Why does pg_relation_size report zero bytes for a distributed table?
--------------------------------------------------------------------

The data in distributed tables lives on the worker nodes (in shards), not on the coordinator. A true measure of distributed table size is obtained as a sum of shard sizes. Citus provides helper functions to query this information. See :ref:`table_size` to learn more.

Why am I seeing an error about max_intermediate_result_size?
------------------------------------------------------------

Citus has to use more than one step to run some queries having subqueries or CTEs. Using :ref:`push_pull_execution`, it pushes subquery results to all worker nodes for use by the main query. If these results are too large, this might cause unacceptable network overhead, or even insufficient storage space on the coordinator node which accumulates and distributes the results.

Citus has a configurable setting, ``citus.max_intermediate_result_size`` to specify a subquery result size threshold at which the query will be canceled. If you run into the error, it looks like:

::

  ERROR:  the intermediate result size exceeds citus.max_intermediate_result_size (currently 1 GB)
  DETAIL:  Citus restricts the size of intermediate results of complex subqueries and CTEs to avoid accidentally pulling large result sets into once place.
  HINT:  To run the current query, set citus.max_intermediate_result_size to a higher value or -1 to disable.

As the error message suggests, you can (cautiously) increase this limit by altering the variable:

.. code-block:: sql

  SET citus.max_intermediate_result_size = '3GB';

Can I run Citus on Microsoft Azure?
-----------------------------------

Yes, Citus is a deployment option of `Azure Database for PostgreSQL <https://docs.microsoft.com/azure/postgresql/>`_ called **Hyperscale**. It is a fully managed database-as-a-service.

Can I run Citus on Amazon RDS?
------------------------------

At this time Amazon does not support running Citus directly on top of Amazon RDS.

What is the state of Citus on AWS?
----------------------------------

Existing customers of :ref:`Citus Cloud <cloud_overview>` can provision a Citus cluster on Amazon Web Services. However we are no longer accepting new signups for Citus Cloud.

For a fully managed Citus database-as-a-service, try `Azure Database for PostgreSQL - Hyperscale (Citus) <https://docs.microsoft.com/en-us/azure/postgresql/overview#azure-database-for-postgresql---hyperscale-citus-preview>`_.

Can I create a new DB in a Citus Cloud instance?
------------------------------------------------

No, but you can use database `schemas <https://www.postgresql.org/docs/current/ddl-schemas.html>`_ to separate and group related sets of tables.

Can I shard by schema on Citus for multi-tenant applications?
-------------------------------------------------------------

It turns out that while storing each tenant's information in a separate schema can be an attractive way to start when dealing with tenants, it leads to problems down the road. In Citus we partition by the tenant_id, and a shard can contain data from several tenants. To learn more about the reason for this design, see our article `Lessons learned from PostgreSQL schema sharding <https://www.citusdata.com/blog/2016/12/18/schema-sharding-lessons/>`_.

How does cstore_fdw work with Citus?
------------------------------------

Citus treats cstore_fdw tables just like regular PostgreSQL tables. When cstore_fdw is used with Citus, each logical shard is created as a foreign cstore_fdw table instead of a regular PostgreSQL table. If your cstore_fdw use case is suitable for the distributed nature of Citus (e.g. large dataset archival and reporting), the two can be used to provide a powerful tool which combines query parallelization, seamless sharding and HA benefits of Citus with superior compression and I/O utilization of cstore_fdw.

What happened to pg_shard?
--------------------------

The pg_shard extension is deprecated and no longer supported.

Starting with the open-source release of Citus v5.x, pg_shard's codebase has been merged into Citus to offer you a unified solution which provides the advanced distributed query planning previously only enjoyed by CitusDB customers while preserving the simple and transparent sharding and real-time writes and reads pg_shard brought to the PostgreSQL ecosystem. Our flagship product, Citus, provides a superset of the functionality of pg_shard and we have migration steps to help existing users to perform a drop-in replacement. Please `contact us <https://www.citusdata.com/about/contact_us>`_ for more information.
