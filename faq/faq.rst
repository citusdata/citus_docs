.. _faq:

Frequently Asked Questions
##########################


Can I create primary keys on distributed tables?
------------------------------------------------

Currently Citus imposes primary key constraint only if the distribution column is a part of the primary key. This assures that the constraint needs to be checked only on one shard to ensure uniqueness.

How do I add nodes to an existing Citus cluster?
------------------------------------------------

You can add nodes to a Citus cluster by calling the master_add_node UDF with the hostname (or IP address) and port number of the new node. After adding a node to an existing cluster, it will not contain any data (shards). Citus will start assigning any newly created shards to this node. To rebalance existing shards from the older nodes to the new node, the Citus Enterprise edition provides a shard rebalancer utility. You can find more information about shard rebalancing in the :ref:`cluster_management` section.

How does Citus handle failure of a worker node?
-----------------------------------------------

If a worker node fails during e.g. a SELECT query, jobs involving shards from that server will automatically fail over to replica shards located on healthy hosts. This means intermittent failures will not require restarting potentially long-running analytical queries, so long as the shards involved can be reached on other healthy hosts.
You can find more information about Citus' failure handling logic in :ref:`dealing_with_node_failures`.

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

If you want to do joins between small dimension tables (regular Postgres tables) and large tables (distributed), then you can distribute the small tables as "reference tables." This creates a single shard replicated across all worker nodes. Citus will then be able to push the join down to the worker nodes. If the local tables you are referring to are large, we generally recommend to distribute the larger tables to reap the benefits of sharding and parallelization which Citus offers. For a deeper discussion, see :ref:`reference_tables` and our :ref:`joins` documentation.

Are there any PostgreSQL features not supported by Citus?
---------------------------------------------------------

Since Citus provides distributed functionality by extending PostgreSQL, it uses the standard PostgreSQL SQL constructs. It provides full SQL support for queries which access a single node in the database cluster. These queries are common, for instance, in multi-tenant applications where different nodes store different tenants (see :ref:`when_to_use_citus`).

Other queries which, by contrast, combine data from multiple nodes, do not support the entire spectrum of PostgreSQL features. However they still enjoy broad SQL coverage, including semi-structured data types (like jsonb, hstore), full text search, operators, functions, and foreign data wrappers. Note that the following constructs aren't supported natively for cross-node queries:

* Window Functions
* CTEs
* Set operations
* Transactional semantics for queries that span across multiple shards

.. _faq_choose_shard_count:

How do I choose the shard count when I hash-partition my data?
--------------------------------------------------------------

One of the choices when first distributing a table is its shard count. This setting can be set differently for each table, and the optimal value depends on use-case. It is possible, but difficult, to change the count after cluster creation, so use these guidelines to choose the right size.

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

Yes, Citus can evaluate count(distinct) aggregates in -- and across -- worker nodes. It also supports the HyperLogLog extension to compute approximate distincts. You can read more details on how to enable approximate :ref:`count_distinct`.

In which situations are uniqueness constraints supported on distributed tables?
-------------------------------------------------------------------------------

Citus is able to enforce a primary key or uniqueness constraint only when the constrained columns contain the distribution column. In particular this means that if a single column constitutes the primary key then it has to be the distribution column as well.

This restriction allows Citus to localize a uniqueness check to a single shard and let PostgreSQL on the worker node do the check efficiently.

Which shard contains data for a particular tenant?
--------------------------------------------------

Citus provides UDFs and metadata tables to determine the mapping of a distribution column value to a particular shard, and the shard placement on a worker node. See :ref:`row_placements` for more details.

I forgot the distribution column of a table, how do I find it?
--------------------------------------------------------------

The Citus coordinator node metadata tables contain this information. See :ref:`finding_dist_col`.

Why does pg_relation_size report zero bytes for a distributed table?
--------------------------------------------------------------------

The data in distributed tables lives on the worker nodes (in shards), not on the coordinator. A true measure of distributed table size is obtained as a sum of shard sizes. Citus provides helper functions to query this information. See :ref:`table_size` to learn more.

Can I run Citus on Heroku or Amazon RDS?
----------------------------------------

At this time Heroku and Amazon do not support running Citus directly on top of Heroku PostgreSQL or Amazon RDS. It is up to them if/when they enable the Citus extension. If you are looking for something similar, `Citus Cloud <https://www.citusdata.com/product/cloud>`_ is our database-as-a-service which we fully manage for you. It runs on top of AWS (like both RDS and Heroku PostgreSQL) and should provide a very similar product experience, with the addition of Citus' horizontal scaling.

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
