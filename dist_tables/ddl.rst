.. _ddl:

Creating Distributed Tables (DDL)
#################################

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:

    ::

        export PATH=/usr/lib/postgresql/9.6/:$PATH

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

In addition to distributing a table as a single replicated shard, the :code:`create_reference_table` UDF marks it as a reference table in the Citus metadata tables. Citus automatically performs two-phase commits (`2PC <https://en.wikipedia.org/wiki/Two-phase_commit_protocol>`_) for modifications to tables marked this way, which provides strong consistency guarantees.

If you have an existing distributed table which has a shard count of one, you can upgrade it to be a recognized reference table by running

.. code-block:: postgresql

  SELECT upgrade_to_reference_table('table_name');

.. _colocation_groups:

Co-Locating Tables
------------------

Co-location is the practice of dividing data tactically, keeping related information on the same machines to enable efficient relational operations, while taking advantage of the horizontal scalability for the whole dataset. For more information and examples see :ref:`colocation`.

Tables are co-located in groups. To manually control a table's co-location group assignment use the optional :code:`colocate_with` parameter of :code:`create_distributed_table`. If you don't care about a table's co-location then omit this parameter. It defaults to the value :code:`'default'`, which groups the table with any other default co-location table having the same distribution column type, shard count, and replication factor.

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

To co-locate a number of tables, distribute one and then put the others into its co-location group. For example:

.. code-block:: postgresql

  -- distribute stores
  SELECT create_distributed_table('stores', 'store_id');

  -- add to the same group as stores
  SELECT create_distributed_table('orders', 'store_id', colocate_with => 'stores');
  SELECT create_distributed_table('products', 'store_id', colocate_with => 'stores');

Information about co-location groups is stored in the :ref:`pg_dist_colocation <colocation_group_table>` table, while :ref:`pg_dist_partition <partition_table>` reveals which tables are assigned to which groups.

.. _marking_colocation:

Upgrading from Citus 5.x
~~~~~~~~~~~~~~~~~~~~~~~~

Starting with Citus 6.0, we made co-location a first-class concept, and started tracking tables' assignment to co-location groups in pg_dist_colocation. Since Citus 5.x didn't have this concept, tables created with Citus 5 were not explicitly marked as co-located in metadata, even when the tables were physically co-located.

Since Citus uses co-location metadata information for query optimization and pushdown, it becomes critical to inform Citus of this co-location for previously created tables. To fix the metadata, simply mark the tables as co-located:

.. code-block:: postgresql

  -- Assume that stores, products and line_items were created in a Citus 5.x database.

  -- Put products and line_items into store's co-location group
  SELECT mark_tables_colocated('stores', ARRAY['products', 'line_items']);

This function requires the tables to be distributed with the same method, column type, number of shards, and replication method. It doesn't re-shard or physically move data, it merely updates Citus metadata.

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;

.. _ddl_prop_support:

Modifying Tables
----------------

Citus automatically propagates many kinds of DDL statements, which means that modifying a distributed table on the coordinator node will update shards on the workers too. Other DDL statements are unsupported on distributed tables, especially those which would modify a distribution column. Attempting to run unsupoorted DDL will raise an error and leave tables on the coordinator node unchanged. Some constraints like primary keys and uniqueness can only be applied prior to distributing a table.

Here is a reference of the categories of DDL statements and whether the current version of Citus supports their propagation. (Note that automatic propagation can be enabled or disabled with a :ref:`configuration parameter <enable_ddl_prop>`.)

General
~~~~~~~

+------------+-----------------------------------+--------------------------------+
| Propagates | DDL                               | Notes                          |
+============+===================================+================================+
| YES        | Adding a Column                   |                                |
+------------+-----------------------------------+--------------------------------+
| YES        | Removing a Column                 | Except the distribution column |
+------------+-----------------------------------+--------------------------------+
| YES        | Changing a Column's Default Value |                                |
+------------+-----------------------------------+--------------------------------+
| YES        | Changing a Column's Data Type     | Except the distribution column |
+------------+-----------------------------------+--------------------------------+
| NO         | Renaming a Column                 |                                |
+------------+-----------------------------------+--------------------------------+
| NO         | Renaming a Table                  |                                |
+------------+-----------------------------------+--------------------------------+

Adding Constraints
~~~~~~~~~~~~~~~~~~

+------------+----------------------+-------------------------------------------------+
| Propagates | DDL                  | Notes                                           |
+============+======================+=================================================+
| YES        | Not-Null Constraints |                                                 |
+------------+----------------------+-------------------------------------------------+
| YES        | Foreign Keys         | Must include distribution column.               |
|            |                      |                                                 |
|            |                      | Requires unique constraint on target column(s). |
+------------+----------------------+-------------------------------------------------+
| NO         | Primary Keys         | Must include distribution column.               |
|            |                      |                                                 |
|            |                      | Add constraint before distributing!             |
+------------+----------------------+-------------------------------------------------+
| NO         | Unique Constraints   | Add constraint before distributing!             |
+------------+----------------------+-------------------------------------------------+
| NO         | Check Constraints    |                                                 |
+------------+----------------------+-------------------------------------------------+


Removing Constraints
~~~~~~~~~~~~~~~~~~~~

+------------+----------------------+
| Propagates | DDL                  |
+============+======================+
| YES        | Not-Null Constraints |
+------------+----------------------+
| YES        | Unique Constraints   |
+------------+----------------------+
| YES        | Primary Keys         |
+------------+----------------------+
| YES        | Foreign Keys         |
+------------+----------------------+
| NO         | Check Constraints    |
+------------+----------------------+
