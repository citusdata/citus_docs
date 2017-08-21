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


Adding a coordinator
----------------------

The Citus coordinator only stores metadata about the table shards and does not store any data. This means that all the computation is pushed down to the workers and the coordinator does only final aggregations on the result of the workers. Therefore, it is not very likely that the coordinator becomes a bottleneck for read performance. Also, it is easy to boost up the coordinator by shifting to a more powerful machine.

However, in some write heavy use cases where the coordinator becomes a performance bottleneck, users can add another coordinator. As the metadata tables are small (typically a few MBs in size), it is possible to copy over the metadata onto another node and sync it regularly. Once this is done, users can send their queries to any coordinator and scale out performance. If your setup requires you to use multiple coordinators, please `contact us <https://www.citusdata.com/about/contact_us>`_.

.. _dealing_with_node_failures:

Dealing With Node Failures
##########################

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
backup tools <http://www.postgresql.org/docs/9.6/static/backup.html>`_ to backup the metadata. Then, they can easily
copy over that metadata to new nodes to resume operation.

.. _tenant_isolation:

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

Running a Query on All Workers
##############################

Broadcasting a statement for execution on all workers is useful for viewing properties of entire worker databases or creating UDFs uniformly throughout the cluster. For example:

.. code-block:: postgresql

  -- Make a UDF available on all workers
  SELECT run_command_on_workers($cmd$ CREATE FUNCTION ...; $cmd$);

  -- List the work_mem setting of each worker database
  SELECT run_command_on_workers($cmd$ SHOW work_mem; $cmd$);

The :code:`run_command_on_workers` function can run only queries which return a single column and single row.

.. _worker_security:

Worker Security
###############

For your convenience getting started, our multi-node installation instructions direct you to set up the :code:`pg_hba.conf` on the workers with its `authentication method <https://www.postgresql.org/docs/current/static/auth-methods.html>`_ set to "trust" for local network connections. However you might desire more security.

To require that all connections supply a hashed password, update the PostgreSQL :code:`pg_hba.conf` on every worker node with something like this:

.. code-block:: bash

  # Require password access to nodes in the local network. The following ranges
  # correspond to 24, 20, and 16-bit blocks in Private IPv4 address spaces.
  host    all             all             10.0.0.0/8              md5

  # Require passwords when the host connects to itself as well
  host    all             all             127.0.0.1/32            md5
  host    all             all             ::1/128                 md5

The coordinator node needs to know roles' passwords in order to communicate with the workers. Add a `.pgpass <https://www.postgresql.org/docs/current/static/libpq-pgpass.html>`_ file to the postgres user's home directory, with a line for each combination of worker address and role:

.. code-block:: ini

  hostname:port:database:username:password

Sometimes workers need to connect to one another, such as during :ref:`repartition joins <repartition_joins>`. Thus each worker node requires a copy of the .pgpass file as well.

Diagnostics
###########

.. _row_placements:

Finding which shard contains data for a specific tenant
-------------------------------------------------------

The rows of a distributed table are grouped into shards, and each shard is placed on a worker node in the Citus cluster. In the multi-tenant Citus use case we can determine which worker node contains the rows for a specific tenant by putting together two pieces of information: the :ref:`shard id <get_shard_id>` associated with the tenant id, and the shard placements on workers. The two can be retrieved together in a single query. Suppose our multi-tenant application's tenants and are stores, and we want to find which worker node holds the data for Gap.com (id=4, suppose).

To find the worker node holding the data for store id=4, ask for the placement of rows whose distribution column has value 4:

.. code-block:: postgresql

  SELECT *
    FROM pg_dist_placement AS placement,
         pg_dist_node AS node
   WHERE placement.groupid = node.groupid
     AND node.noderole = 'primary'
     AND shardid = (
       SELECT get_shard_id_for_distribution_column('stores', 4)
     );

The output contains the host and port of the worker database.

::

  ┌─────────┬────────────┬─────────────┬───────────┬──────────┬─────────────┐
  │ shardid │ shardstate │ shardlength │ nodename  │ nodeport │ placementid │
  ├─────────┼────────────┼─────────────┼───────────┼──────────┼─────────────┤
  │  102009 │          1 │           0 │ localhost │     5433 │           2 │
  └─────────┴────────────┴─────────────┴───────────┴──────────┴─────────────┘

.. _finding_dist_col:

Finding the distribution column for a table
-------------------------------------------

Each distributed table in Citus has a "distribution column." For more information about what this is and how it works, see :ref:`Distributed Data Modeling <distributed_data_modeling>`. There are many situations where it is important to know which column it is. Some operations require joining or filtering on the distribution column, and you may encounter error messages with hints like, "add a filter to the distribution column."

The :code:`pg_dist_*` tables on the coordinator node contain diverse metadata about the distributed database. In particular :code:`pg_dist_partition` holds information about the distribution column (formerly called *partition* column) for each table. You can use a convenient utility function to look up the distribution column name from the low-level details in the metadata. Here's an example and its output:

.. code-block:: postgresql

  -- create example table

  CREATE TABLE products (
    store_id bigint,
    product_id bigint,
    name text,
    price money,

    CONSTRAINT products_pkey PRIMARY KEY (store_id, product_id)
  );

  -- pick store_id as distribution column

  SELECT create_distributed_table('products', 'store_id');

  -- get distribution column name for products table

  SELECT column_to_column_name(logicalrelid, partkey) AS dist_col_name
    FROM pg_dist_partition
   WHERE logicalrelid='products'::regclass;

Output:

::

  ┌───────────────┐
  │ dist_col_name │
  ├───────────────┤
  │ store_id      │
  └───────────────┘
