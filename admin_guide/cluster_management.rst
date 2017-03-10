.. _cluster_management:

Cluster Management
$$$$$$$$$$$$$$$$$$

In this section, we discuss how you can add or remove nodes from your Citus cluster and how you can deal with node failures.

.. note::
  To make moving shards across nodes or re-replicating shards on failed nodes easier, Citus Enterprise comes with a shard rebalancer extension. We discuss briefly about the functions provided by the shard rebalancer as and when relevant in the sections below. You can learn more about these functions, their arguments and usage, in the :ref:`cluster_management_functions` reference section.

.. _scaling_out_cluster:

Scaling out your cluster
########################

Citus’s logical sharding based architecture allows you to scale out your cluster without any down time. This section describes how you can add more nodes to your Citus cluster in order to improve query performance / scalability.

.. _adding_worker_node:

Adding a worker
----------------------

Citus stores all the data for distributed tables on the worker nodes. Hence, if you want to scale out your cluster by adding more computing power, you can do so by adding a worker.

To add a new node to the cluster, you first need to add the DNS name or IP address of that node and port (on which PostgreSQL is running) in the pg_dist_node catalog table. You can do so using the :ref:`master_add_node` UDF. Example:

::

   SELECT * from master_add_node('node-name', 5432);

In addition to the above, if you want to move existing shards to the newly added worker, Citus Enterprise provides an additional rebalance_table_shards function to make this easier. This function will move the shards of the given table to make them evenly distributed among the workers.

::

	select rebalance_table_shards('github_events');

Adding a worker with :code:`master_add_node` automatically replicates existing reference tables to the new node. For very large reference tables this can be a costly operation. Some users may want to separate "getting the new node on the books" from the copying of reference data to it. Citus provides the :code:`master_add_inactive_node()` function for this scenario. The idea is to create a new node as temporarily inactive, perform custom actions, and then activate the node:

.. code-block:: postgresql

  -- First add the node as inactive. The coordinator will not route any
  -- queries to this node.
  SELECT * from master_add_inactive_node('node-name', 5432);

  -- Next do custom tasks, retrying as necessary
  -- ...

  -- Finally mark the node as active.
  SELECT * from master_activate_node('node-name', 5432);

Adding a master
----------------------

The Citus master only stores metadata about the table shards and does not store any data. This means that all the computation is pushed down to the workers and the master does only final aggregations on the result of the workers. Therefore, it is not very likely that the master becomes a bottleneck for read performance. Also, it is easy to boost up the master by shifting to a more powerful machine.

However, in some write heavy use cases where the master becomes a performance bottleneck, users can add another master. As the metadata tables are small (typically a few MBs in size), it is possible to copy over the metadata onto another node and sync it regularly. Once this is done, users can send their queries to any master and scale out performance. If your setup requires you to use multiple masters, please `contact us <https://www.citusdata.com/about/contact_us>`_.

.. _dealing_with_node_failures:

Dealing With Node Failures
##########################

In this sub-section, we discuss how you can deal with node failures without incurring any downtime on your Citus cluster. We first discuss how Citus handles worker failures automatically by maintaining multiple replicas of the data. We also briefly describe how users can replicate their shards to bring them to the desired replication factor in case a node is down for a long time. Lastly, we discuss how you can setup redundancy and failure handling mechanisms for the master.

.. _worker_node_failures:

Worker Node Failures
--------------------

Citus supports two modes of replication, allowing it to tolerate worker-node failures. In the first model, we use PostgreSQL's streaming replication to replicate the entire worker-node as-is. In the second model, Citus can replicate data modification statements, thus replicating shards across different worker nodes. They have different advantages depending on the workload and use-case as discussed below:

1. **PostgreSQL streaming replication.** This option is best for heavy OLTP workloads. It replicates entire worker nodes by continuously streaming their WAL records to a standby. You can configure streaming replication on-premise yourself by consulting the `PostgreSQL replication documentation <https://www.postgresql.org/docs/current/static/warm-standby.html#STREAMING-REPLICATION>`_ or use :ref:`Citus Cloud <cloud_overview>` which is pre-configured for replication and high-availability.

2. **Citus shard replication.** This option is best suited for an append-only workload. Citus replicates shards across different nodes by automatically replicating DML statements and managing consistency. If a node goes down, the co-ordinator node will continue to serve queries by routing the work to the replicas seamlessly. To enable shard replication simply set :code:`SET citus.shard_replication_factor = 2;` (or higher) before distributing data to the cluster.

.. _master_node_failures:

Master Node Failures
--------------------

The Citus master maintains metadata tables to track all of the cluster nodes and the locations of the database shards on those nodes. The metadata tables are small (typically a few MBs in size) and do not change very often. This means that they can be replicated and quickly restored if the node ever experiences a failure. There are several options on how users can deal with master failures.

1. **Use PostgreSQL streaming replication:** You can use PostgreSQL's streaming
replication feature to create a hot standby of the master. Then, if the primary
master node fails, the standby can be promoted to the primary automatically to
serve queries to your cluster. For details on setting this up, please refer to the `PostgreSQL wiki <https://wiki.postgresql.org/wiki/Streaming_Replication>`_.

2. Since the metadata tables are small, users can use EBS volumes, or `PostgreSQL
backup tools <http://www.postgresql.org/docs/9.6/static/backup.html>`_ to backup the metadata. Then, they can easily
copy over that metadata to new nodes to resume operation.

3. Citus's metadata tables are simple and mostly contain text columns which
are easy to understand. So, in case there is no failure handling mechanism in
place for the master node, users can dynamically reconstruct this metadata from
shard information available on the worker nodes. To learn more about the metadata
tables and their schema, you can visit the :ref:`metadata_tables` section of our documentation.

Tenant Isolation
################

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

  ┌─────────────────────────────┐
  │ isolate_tenant_to_new_shard │
  ├─────────────────────────────┤
  │                      102240 │
  └─────────────────────────────┘

The new shard(s) are created on the same node as the shard(s) from which the tenant was removed. For true hardware isolation they can be moved to a separate node in the Citus cluster. As mentioned, the :code:`isolate_tenant_to_new_shard` function returns the newly created shard id, and this id can be used to move the shard:

.. code-block:: postgresql

  -- find the node currently holding the new shard
  SELECT nodename, nodeport
    FROM pg_dist_shard_placement
   WHERE shardid = 102240;

  -- list the available worker nodes that could hold the shard
  SELECT * FROM master_get_active_worker_nodes();

  -- move the shard to your choice of worker
  -- (it will also move any shards created with the CASCADE option)
  SELECT master_move_shard_placement(
    102240,
    'source_host', source_port,
    'dest_host', dest_port);

Diagnostics
###########

.. _row_placements:

Finding which shard contains data for a specific tenant
-------------------------------------------------------

The rows of a distributed table are grouped into shards, and each shard is placed on a worker node in the Citus cluster. In the multi-tenant Citus use case we can determine which worker node contains the rows for a specific tenant by putting together two pieces of information: the :ref:`shard id <get_shard_id>` associated with the tenant id, and the shard placements on workers. The two can be retrieved together in a single query. Suppose our multi-tenant application's tenants and are stores, and we want to find which worker node holds the data for Gap.com (id=4, suppose).

To find the worker node holding the data for store id=4, ask for the placement of rows whose distribution column has value 4:

.. code-block:: postgresql

  SELECT *
    FROM pg_dist_shard_placement
   WHERE shardid = (
     SELECT get_shard_id_for_distribution_column('stores', 4)
   );

The output contains the host and port of the worker database.

::

  ┌─────────┬────────────┬─────────────┬───────────┬──────────┬─────────────┐
  │ shardid │ shardstate │ shardlength │ nodename  │ nodeport │ placementid │
  ├─────────┼────────────┼─────────────┼───────────┼──────────┼─────────────┤
  │  102009 │          1 │           0 │ localhost │     5433 │           2 │
  └─────────┴────────────┴─────────────┴───────────┴──────────┴─────────────┘

