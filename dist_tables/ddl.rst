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

Co-Locating Tables
------------------

Co-location is the practice of dividing data tactically, keeping related information on the same machines to enable efficient relational operations, while taking advantage of the horizontal scalability for the whole dataset. For more information and examples see :ref:`colocation`.

Tables are co-located in groups. To manually control a table's co-location group assignment use the optional :code:`colocate_with` parameter of :code:`create_distributed_table`. If you don't care about a table's co-location then omit this parameter. It defaults to the value :code:`'default'`, which groups the table with any other default co-location table having the same distribution column type and shard count.

.. code-block:: postgresql

  -- these tables are implicitly co-located by using the same
  -- distribution column type and shard count with the default
  -- co-location group

  SELECT create_distributed_table('A', 'some_int_col');
  SELECT create_distributed_table('B', 'other_int_col');

If you would prefer a table to be in its own co-location group, specify :code:`'none'`.

.. code-block:: postgresql

  -- not co-located with other tables

  SELECT create_distributed_table('A', 'foo', colocate_with => 'none');

To co-locate a number of tables, create one in its own group, then add the others.

.. code-block:: postgresql

  -- start a new group
  SELECT create_distributed_table('A', 'foo', colocate_with => 'none');

  -- add to the same group as A
  SELECT create_distributed_table('B', 'bar', colocate_with => 'A');
  SELECT create_distributed_table('C', 'baz', colocate_with => 'A');

Information about co-location groups is stored in :code:`pg_dist_colocation`, while :code:`pg_dist_partition` reveals which tables are assigned to which groups:

::

  Table "pg_catalog.pg_dist_colocation"
  ┌────────────────────────┬─────────┬───────────┐
  │         Column         │  Type   │ Modifiers │
  ├────────────────────────┼─────────┼───────────┤
  │ colocationid           │ integer │ not null  │
  │ shardcount             │ integer │ not null  │
  │ replicationfactor      │ integer │ not null  │
  │ distributioncolumntype │ oid     │ not null  │
  └────────────────────────┴─────────┴───────────┘

  Table "pg_catalog.pg_dist_partition"
  ┌──────────────┬──────────┬──────────────────────────────┐
  │    Column    │   Type   │          Modifiers           │
  ├──────────────┼──────────┼──────────────────────────────┤
  │ logicalrelid │ regclass │ not null                     │
  │ partmethod   │ "char"   │ not null                     │
  │ partkey      │ text     │                              │
  │ colocationid │ integer  │ not null default 0           │
  │ repmodel     │ "char"   │ not null default 'c'::"char" │
  └──────────────┴──────────┴──────────────────────────────┘

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;
