Frequently Asked Questions
##########################


Can I create primary keys on distributed tables?
------------------------------------------------

Currently Citus imposes primary key constraint only if the distribution column is a part of the primary key. This assures that the constraint needs to be checked only on one shard to ensure uniqueness.

How do I add nodes to an existing Citus cluster?
------------------------------------------------

You can add nodes to a Citus cluster by adding the DNS host name and port of the new node to the pg_worker_list.conf configuration file in the data directory. After adding a node to an existing cluster, it will not contain any data (shards). Citus will start assigning any newly created shards to this node. To rebalance existing shards from the older nodes to the new node, the Citus Enterprise edition provides a shard rebalancer utility. You can find more information about shard rebalancing in the :ref:`cluster_management` section

How do I change the shard count for a hash partitioned table?
-------------------------------------------------------------

Optimal shard count is related to the total number of cores on the workers. Citus partitions an incoming query into its fragment queries which run on individual worker shards. Hence the degree of parallelism for each query is governed by the number of shards the query hits. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core.

We typically recommend creating a high number of initial shards, e.g. 2x or 4x the number of current CPU cores. This allows for future scaling if you add more workers and CPU cores.

How does citus handle failure of a worker node?
----------------------------------------------

If a worker node fails during e.g. a SELECT query, jobs involving shards from that server will automatically fail over to replica shards located on healthy hosts. This means intermittent failures will not require restarting potentially long-running analytical queries, so long as the shards involved can be reached on other healthy hosts.
You can find more information about Citus' failure handling logic in :ref:`dealing_with_node_failures`.

How does Citus handle failover of the master node?
--------------------------------------------------

As the Citus master node is similar to a standard PostgreSQL server, regular PostgreSQL synchronous replication and failover can be used to provide higher availability of the master node. Many of our customers use synchronous replication in this way to add resilience against master node failure. You can find more information about handling :ref:`master_node_failures`.

How do I ingest the results of a query into a distributed table?
----------------------------------------------------------------

Citus currently doesn't support the INSERT / SELECT syntax for copying the results of a query into a distributed table. As a simple workaround, you could use

::

  psql -c "COPY (query) TO STDOUT" | \
  psql -c "COPY table FROM STDIN"

In addition to the above, there are other workarounds which are more complex to implement but are more efficient. Please contact us if your use-case demands such ingest workflows.

Can I join distributed and non-distributed tables together in the same query?
-----------------------------------------------------------------------------

If you want to do joins between small dimension tables (regular Postgres tables) and large tables (distributed), then you could distribute the small tables by creating 1 shard and N (with N being the number of workers) replicas. Citus will then be able to push the join down to the worker nodes. If the local tables you are referring to are large, we generally recommend to distribute the larger tables to reap the benefits of sharding and parallelization which Citus offers. For a deeper discussion into the way Citus handles joins, please see our :ref:`joins` documentation.

Are there any PostgreSQL features not supported by CitusDB?
-----------------------------------------------------------

Since Citus provides distributed functionality by extending PostgreSQL, it uses the standard PostgreSQL SQL constructs. This includes the support for wide range of data types (including semi-structured data types like jsonb, hstore), full text search, operators and functions, foreign data wrappers, etc.

PostgreSQL has a wide SQL coverage; and Citus does not support that entire spectrum out of the box when querying distributed tables. Some constructs which aren't supported natively for distributed tables are:

* Window Functions
* CTEs
* Set operations
* Transactional semantics for queries that span across multiple shards

It is important to note that you can still run all of those queries on regular PostgreSQL tables in the Citus cluster. As a result, you can address many use cases through a combination of rewriting the queries and/or adding some extensions. We are working on increasing the distributed SQL coverage for Citus to further simplify these queries. So, if you run into an unsupported construct, please contact us and we will do our best to help you out.

How do I choose the shard count when I hash-partition my data?
--------------------------------------------------------------
.. _faq_choose_shard_count:

Optimal shard count is related to the total number of cores on the workers. Citus partitions an incoming query into its fragment queries which run on individual worker shards. Hence, the degree of parallelism for each query is governed by the number of shards the query hits. To ensure maximum parallelism, you should create enough shards on each node such that there is at least one shard per CPU core.

We typically recommend creating a high number of initial shards, e.g. 2x or 4x the number of current CPU cores. This allows for future scaling if you add more workers and CPU cores.

How does citus support count(distinct) queries?
-----------------------------------------------

Citus can push down count(distinct) entirely down to the worker nodes in certain situations (for example if the distinct is on the distribution column or is grouped by the distribution column in hash-partitioned tables). In other situations, Citus uses the HyperLogLog extension to compute approximate distincts. You can read more details on how to enable approximate :ref:`count_distinct`.

In which situations are uniqueness constraints supported on distributed tables?
-------------------------------------------------------------------------------

Citus is able to enforce a primary key or uniqueness constraint only when the constrained columns contain the distribution column. In particular this means that if a single column constitutes the primary key then it has to be the distribution column as well.

This restriction allows Citus to localize a uniqueness check to a single shard and let PostgreSQL on the worker node do the check efficiently.
