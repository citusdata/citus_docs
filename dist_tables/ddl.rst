.. _ddl:

Creating Distributed Tables (DDL)
#################################

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:

    ::

        export PATH=/usr/lib/postgresql/9.6/:$PATH

We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Creating And Distributing Tables
--------------------------------

To create a distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.6/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

::

    psql -h localhost -d postgres
    CREATE TABLE github_events
    (
    	event_id bigint,
    	event_type text,
    	event_public boolean,
    	repo_id bigint,
    	payload jsonb,
    	repo jsonb,
    	actor jsonb,
    	org jsonb,
    	created_at timestamp
    );

Next, you can use the create_distributed_table() function to specify the table
distribution column and create the worker shards.

::

    SELECT create_distributed_table('github_events', 'repo_id');

This function informs Citus that the github_events table should be distributed
on the repo_id column (by hashing the column value). The function also creates
shards on the worker nodes using the citus.shard_count and
citus.shard_replication_factor configuration values.

This example would create a total of citus.shard_count number of shards where each
shard owns a portion of a hash token space and gets replicated based on the
default citus.shard_replication_factor configuration value. The shard replicas
created on the worker have the same table schema, index, and constraint
definitions as the table on the master. Once the replicas are created, this
function saves all distributed metadata on the master.

Each created shard is assigned a unique shard id and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. You can connect to the worker postgres instances to view or run commands on individual shards.

You are now ready to insert data into the distributed table and run queries on it. You can also learn more about the UDF used in this section in the :ref:`user_defined_functions` of our documentation.

Reference Tables
~~~~~~~~~~~~~~~~

The above method distributes tables into multiple horizontal shards, but it's also possible to distribute tables into a single shard and replicate it to every worker node. Tables distributed this way are called *reference tables.*  They are typically small non-partitioned tables which we want to locally join with other tables on any worker. One US-centric example is information about states.

.. code-block:: postgresql

  -- a reference table

  CREATE TABLE states (
    code char(2) PRIMARY KEY,
    full_name text NOT NULL,
    general_sales_tax numeric(4,3)
  );

  -- distribute it to all workers

  SELECT create_reference_table('states');

Other queries, such as one calculating tax for a shopping cart, can join on the :code:`states` table with no network overhead.

.. _colocation_groups:

Co-Location Groups
------------------

Table rows are stored in shards across a Citus cluster. When all rows needed by a query are available in a single shard then the tables named by the query are said to be *co-located for the query*. (Tables which are co-located for the majority of queries in an application are simply called co-located tables.) Queries with co-located tables excute faster because Citus doesn't need to shuffle data over the network.

When the database administrator changes the number of worker nodes in a cluster, they run the Citus shard rebalancer to redistribute shards evenly. It's important to preserve table co-location during this process to
keep queries fast. Because tables are co-located with respect to particular queries there is no one-size-fits-all algorithm to preserve co-location, and Citus' shard rebalancer uses a cautious heuristic. It keeps rows together when there is even a possibility that their distribution columns might be joined. Specifically it keeps them together when their distribution columns have the same data type and their distribution method is the same.

Shard rebalancing must take table locks for any tables it decides must stay together. The default heuristic can result in false-positives, causing unnecessary locking and slower rebalancing. Citus allows the database administrator to customize which tables should maintain co-location -- and importantly which tables should not.

To control co-location groups manually use the optional :code:`colocate_with` parameter of :code:`create_distributed_table`. Left unspecified it defaults to the value :code:`default` which lumps all tables having the same distribution column type into the same co-location group.

To start a new group and add tables to it use the two other modes of :code:`colocate_with`: the reserved string :code:`none` and the name of another table.

.. code-block:: sql

  -- start a new group
  SELECT create_distributed_table('products', 'store_id', colocate_with => 'none');

  -- add to the same group as products
  SELECT create_distributed_table('orders', 'store_id', colocate_with => 'products');

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;
