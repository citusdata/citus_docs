.. _ddl:

Creating and Modifying Distributed Tables (DDL)
###############################################

Creating And Distributing Tables
--------------------------------

To create a distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/current/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

::

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
definitions as the table on the coordinator. Once the replicas are created, this
function saves all distributed metadata on the coordinator.

Each created shard is assigned a unique shard id and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. You can connect to the worker postgres instances to view or run commands on individual shards.

You are now ready to insert data into the distributed table and run queries on it. You can also learn more about the UDF used in this section in the :ref:`user_defined_functions` of our documentation.

.. _reference_tables:

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

Distributing Coordinator Data
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If an existing PostgreSQL database is converted into the coordinator node for a Citus cluster, the data in its tables can be distributed efficiently and with minimal interruption to an application.

The :code:`create_distributed_table` function described earlier works on both empty and non-empty tables, and for the latter automatically distributes table rows throughout the cluster. You will know if it does this by the presence of the message, "NOTICE:  Copying data from local table..." For example:

.. code-block:: postgresql

  CREATE TABLE series AS SELECT i FROM generate_series(1,1000000) i;
  SELECT create_distributed_table('series', 'i');
  NOTICE:  Copying data from local table...
   create_distributed_table
   --------------------------

   (1 row)

Writes on the table are blocked while the data is migrated, and pending writes are handled as distributed queries once the function commits. (If the function fails then the queries become local again.) Reads can continue as normal and will become distributed queries once the function commits.

.. note::

  When distributing a number of tables with foreign keys between them, it's best to drop the foreign keys before running :code:`create_distributed_table` and recreating them after distributing the tables. Foreign keys cannot always be enforced when one table is distributed and the other is not.

When migrating data from an external database, such as from Amazon RDS to Citus Cloud, first create the Citus distributed tables via :code:`create_distributed_table`, then copy the data into the table.

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

Citus automatically propagates many kinds of DDL statements, which means that modifying a distributed table on the coordinator node will update shards on the workers too. Other DDL statements require manual propagation, and certain others are prohibited such as those which would modify a distribution column. Attempting to run DDL that is ineligible for automatic propagation will raise an error and leave tables on the coordinator node unchanged.

By default Citus performs DDL with a one-phase commit protocol. For greater safety you can enable two-phase commits by setting

.. code-block:: postgresql

  SET citus.multi_shard_commit_protocol = '2pc';

Here is a reference of the categories of DDL statements which propagate. Note that automatic propagation can be enabled or disabled with a :ref:`configuration parameter <enable_ddl_prop>`.

Adding/Modifying Columns
~~~~~~~~~~~~~~~~~~~~~~~~

Citus propagates most `ALTER TABLE <https://www.postgresql.org/docs/current/static/ddl-alter.html>`_ commands automatically. Adding columns or changing their default values work as they would in a single-machine PostgreSQL database:

.. code-block:: postgresql

  -- Adding a column

  ALTER TABLE products ADD COLUMN description text;

  -- Changing default value

  ALTER TABLE products ALTER COLUMN price SET DEFAULT 7.77;

Significant changes to an existing column are fine too, except for those applying to the :ref:`distribution column <distributed_data_modeling>`. This column determines how table data distributes through the Citus cluster and cannot be modified in a way that would change data distribution.


.. code-block:: postgresql

  -- Cannot be executed against a distribution column

  -- Removing a column

  ALTER TABLE products DROP COLUMN description;

  -- Changing column data type

  ALTER TABLE products ALTER COLUMN price TYPE numeric(10,2);

  -- Renaming a column

  ALTER TABLE products RENAME COLUMN product_no TO product_number;

Adding/Removing Constraints
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Using Citus allows you to continue to enjoy the safety of a relational database, including database constraints (see the PostgreSQL `docs <https://www.postgresql.org/docs/current/static/ddl-constraints.html>`_). Due to the nature of distributed systems, Citus will not cross-reference uniqueness constraints or referential integrity between worker nodes. Foreign keys must always be declared between :ref:`colocated tables <colocation>`. To do this, use compound foreign keys that include the distribution column.

This example, excerpted from a :ref:`typical_mt_schema`, shows how to create primary and foreign keys on distributed tables.

.. code-block:: postgresql

  --
  -- Adding a primary key
  -- --------------------

  -- Ultimately we'll distribute these tables on the account id, so the
  -- ads and clicks tables use compound keys to include it.

  ALTER TABLE accounts ADD PRIMARY KEY (id);
  ALTER TABLE ads ADD PRIMARY KEY (account_id, id);
  ALTER TABLE clicks ADD PRIMARY KEY (account_id, id);

  -- Next distribute the tables
  -- (primary keys must be created prior to distribution)

  SELECT create_distributed_table('accounts',  'id');
  SELECT create_distributed_table('ads',       'account_id');
  SELECT create_distributed_table('clicks',    'account_id');

  --
  -- Adding foreign keys
  -- -------------------

  -- Note that this can happen before or after distribution, as long as
  -- there exists a uniqueness constraint on the target column(s) which
  -- can only be enforced before distribution.

  ALTER TABLE ads ADD CONSTRAINT ads_account_fk
    FOREIGN KEY (account_id) REFERENCES accounts (id);
  ALTER TABLE clicks ADD CONSTRAINT clicks_account_fk
    FOREIGN KEY (account_id) REFERENCES accounts (id);

Uniqueness constraints, like primary keys, must be added prior to table distribution.

.. code-block:: postgresql

  -- Suppose we want every ad to use a unique image. Notice we can
  -- enforce it only per account when we distribute by account id.

  ALTER TABLE ads ADD CONSTRAINT ads_unique_image
    UNIQUE (account_id, image_url);

Not-null constraints can always be applied because they require no lookups between workers.

.. code-block:: postgresql

  ALTER TABLE ads ALTER COLUMN image_url SET NOT NULL;

Adding/Removing Indices
~~~~~~~~~~~~~~~~~~~~~~~

Citus supports adding and removing `indices <https://www.postgresql.org/docs/current/static/sql-createindex.html>`_:

.. code-block:: postgresql

  -- Adding an index

  CREATE INDEX clicked_at_idx ON clicks USING BRIN (clicked_at);

  -- Removing an index

  DROP INDEX clicked_at_idx;

Adding an index takes a write lock, which can be undesirable in a multi-tenant "system-of-record." To minimize application downtime, create the index `concurrently <https://www.postgresql.org/docs/current/static/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY>`_ instead. This method requires more total work than a standard index build and takes significantly longer to complete. However, since it allows normal operations to continue while the index is built, this method is useful for adding new indexes in a production environment.

.. code-block:: postgresql

  -- Adding an index without locking table writes

  CREATE INDEX CONCURRENTLY clicked_at_idx ON clicks USING BRIN (clicked_at);

Manual Modification
~~~~~~~~~~~~~~~~~~~

Currently other DDL commands are not auto-propagated, however you can propagate the changes manually using this general four-step outline:

1. Begin a transaction and take an ACCESS EXCLUSIVE lock on coordinator node against the table in question.
2. In a separate connection, connect to each worker node and apply the operation to all shards.
3. Disable DDL propagation on the coordinator and run the DDL command there.
4. Commit the transaction (which will release the lock).

Contact us for guidance about the process, we have internal tools which can make it easier.
