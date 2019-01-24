.. _ddl:

Creating and Modifying Distributed Tables (DDL)
===============================================

.. note::

   Citus (including :ref:`mx`) requires that DDL commands be run from the coordinator node only.

Creating And Distributing Tables
--------------------------------

To create a distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/current/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

.. code-block:: sql

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

.. code-block:: sql

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

The above method distributes tables into multiple horizontal shards, but another possibility is distributing tables into a single shard and replicating the shard to every worker node. Tables distributed this way are called *reference tables.* They are used to store data that needs to be frequently accessed by multiple nodes in a cluster.

Common candidates for reference tables include:

* Smaller tables which need to join with larger distributed tables.
* Tables in multi-tenant apps which lack a tenant id column or which aren't associated with a tenant. (In some cases, to reduce migration effort, users might even choose to make reference tables out of tables associated with a tenant but which currently lack a tenant id.)
* Tables which need unique constraints across multiple columns and are small enough.

For instance suppose a multi-tenant eCommerce site needs to calculate sales tax for transactions in any of its stores. Tax information isn't specific to any tenant. It makes sense to consolidate it in a shared table. A US-centric reference table might look like this:

.. code-block:: postgresql

  -- a reference table

  CREATE TABLE states (
    code char(2) PRIMARY KEY,
    full_name text NOT NULL,
    general_sales_tax numeric(4,3)
  );

  -- distribute it to all workers

  SELECT create_reference_table('states');

Now queries such as one calculating tax for a shopping cart can join on the :code:`states` table with no network overhead, and can add a foreign key to the state code for better validation.

In addition to distributing a table as a single replicated shard, the :code:`create_reference_table` UDF marks it as a reference table in the Citus metadata tables. Citus automatically performs two-phase commits (`2PC <https://en.wikipedia.org/wiki/Two-phase_commit_protocol>`_) for modifications to tables marked this way, which provides strong consistency guarantees.

If you have an existing distributed table which has a shard count of one, you can upgrade it to be a recognized reference table by running

.. code-block:: postgresql

  SELECT upgrade_to_reference_table('table_name');

For another example of using reference tables in a multi-tenant application, see :ref:`mt_ref_tables`.

Distributing Coordinator Data
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If an existing PostgreSQL database is converted into the coordinator node for a Citus cluster, the data in its tables can be distributed efficiently and with minimal interruption to an application.

The :code:`create_distributed_table` function described earlier works on both empty and non-empty tables, and for the latter it automatically distributes table rows throughout the cluster. You will know if it does this by the presence of the message, "NOTICE:  Copying data from local table..." For example:

.. code-block:: postgresql

  CREATE TABLE series AS SELECT i FROM generate_series(1,1000000) i;
  SELECT create_distributed_table('series', 'i');
  NOTICE:  Copying data from local table...
   create_distributed_table
   --------------------------

   (1 row)

Writes on the table are blocked while the data is migrated, and pending writes are handled as distributed queries once the function commits. (If the function fails then the queries become local again.) Reads can continue as normal and will become distributed queries once the function commits.

.. note::

  When distributing a number of tables with foreign keys between them, it's best to drop the foreign keys before running :code:`create_distributed_table` and recreating them after distributing the tables. Foreign keys cannot always be enforced when one table is distributed and the other is not. However foreign keys *are* supported between distributed tables and reference tables.

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

When a new table is not related to others in its would-be implicit co-location group, specify :code:`colocated_with => 'none'`.

.. code-block:: postgresql

  -- not co-located with other tables

  SELECT create_distributed_table('A', 'foo', colocate_with => 'none');

Splitting unrelated tables into their own co-location groups will improve :ref:`shard rebalancing <shard_rebalancing>` performance, because shards in the same group have to be moved together.

When tables are indeed related (for instance when they will be joined), it can make sense to explicitly co-locate them. The gains of appropriate co-location are more important than any rebalancing overhead.

To explicitly co-locate multiple tables, distribute one and then put the others into its co-location group. For example:

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

Since Citus uses co-location metadata information for query optimization and pushdown, it becomes critical to inform Citus of this co-location for previously created tables. To fix the metadata, simply mark the tables as co-located using :ref:`mark_tables_colocated`:

.. code-block:: postgresql

  -- Assume that stores, products and line_items were created in a Citus 5.x database.

  -- Put products and line_items into store's co-location group
  SELECT mark_tables_colocated('stores', ARRAY['products', 'line_items']);

This function requires the tables to be distributed with the same method, column type, number of shards, and replication method. It doesn't re-shard or physically move data, it merely updates Citus metadata.

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

.. code-block:: sql

    DROP TABLE github_events;

.. _ddl_prop_support:

Modifying Tables
----------------

Citus automatically propagates many kinds of DDL statements, which means that modifying a distributed table on the coordinator node will update shards on the workers too. Other DDL statements require manual propagation, and certain others are prohibited such as those which would modify a distribution column. Attempting to run DDL that is ineligible for automatic propagation will raise an error and leave tables on the coordinator node unchanged.

Here is a reference of the categories of DDL statements which propagate. Note that automatic propagation can be enabled or disabled with a :ref:`configuration parameter <enable_ddl_prop>`.

Adding/Modifying Columns
~~~~~~~~~~~~~~~~~~~~~~~~

Citus propagates most `ALTER TABLE <https://www.postgresql.org/docs/current/static/ddl-alter.html>`_ commands automatically. Adding columns or changing their default values work as they would in a single-machine PostgreSQL database:

.. code-block:: postgresql

  -- Adding a column

  ALTER TABLE products ADD COLUMN description text;

  -- Changing default value

  ALTER TABLE products ALTER COLUMN price SET DEFAULT 7.77;

Significant changes to an existing column like renaming it or changing its data type are fine too. However the data type of the :ref:`distribution column <distributed_data_modeling>` cannot be altered. This column determines how table data distributes through the Citus cluster, and modifying its data type would require moving the data.

Attempting to do so causes an error:

.. code-block:: postgres

  -- assumining store_id is the distribution column
  -- for products, and that it has type integer

  ALTER TABLE products
  ALTER COLUMN store_id TYPE text;

  /*
  ERROR:  XX000: cannot execute ALTER TABLE command involving partition column
  LOCATION:  ErrorIfUnsupportedAlterTableStmt, multi_utility.c:2150
  */

Adding/Removing Constraints
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Using Citus allows you to continue to enjoy the safety of a relational database, including database constraints (see the PostgreSQL `docs <https://www.postgresql.org/docs/current/static/ddl-constraints.html>`_). Due to the nature of distributed systems, Citus will not cross-reference uniqueness constraints or referential integrity between worker nodes.

Foreign keys may be created in these situations:

* between two local (non-distributed) tables,
* between two :ref:`colocated <colocation>` distributed tables when the key includes the distribution column, or
* as a distributed table referencing a :ref:`reference table <reference_tables>`

Reference tables are not supported as the *referencing* table of a foreign key constraint, i.e. keys from reference to reference and reference to distributed are not supported.

To set up a foreign key between colocated distributed tables, always include the distribution column in the key. This may involve making the key compound.

.. note::

  Primary keys and uniqueness constraints must include the distribution column. Adding them to a non-distribution column will generate an error (see :ref:`non_distribution_uniqueness`).

This example shows how to create primary and foreign keys on distributed tables:

.. code-block:: postgresql

  --
  -- Adding a primary key
  -- --------------------

  -- We'll distribute these tables on the account_id. The ads and clicks
  -- tables must use compound keys that include account_id.

  ALTER TABLE accounts ADD PRIMARY KEY (id);
  ALTER TABLE ads ADD PRIMARY KEY (account_id, id);
  ALTER TABLE clicks ADD PRIMARY KEY (account_id, id);

  -- Next distribute the tables

  SELECT create_distributed_table('accounts', 'id');
  SELECT create_distributed_table('ads',      'account_id');
  SELECT create_distributed_table('clicks',   'account_id');

  --
  -- Adding foreign keys
  -- -------------------

  -- Note that this can happen before or after distribution, as long as
  -- there exists a uniqueness constraint on the target column(s) which
  -- can only be enforced before distribution.

  ALTER TABLE ads ADD CONSTRAINT ads_account_fk
    FOREIGN KEY (account_id) REFERENCES accounts (id);
  ALTER TABLE clicks ADD CONSTRAINT clicks_ad_fk
    FOREIGN KEY (account_id, ad_id) REFERENCES ads (account_id, id);

Similarly, include the distribution column in uniqueness constraints:

.. code-block:: postgresql

  -- Suppose we want every ad to use a unique image. Notice we can
  -- enforce it only per account when we distribute by account id.

  ALTER TABLE ads ADD CONSTRAINT ads_unique_image
    UNIQUE (account_id, image_url);

Not-null constraints can be applied to any column (distribution or not) because they require no lookups between workers.

.. code-block:: postgresql

  ALTER TABLE ads ALTER COLUMN image_url SET NOT NULL;

Using NOT VALID Constraints
~~~~~~~~~~~~~~~~~~~~~~~~~~~

In some situations it can be useful to enforce constraints for new rows, while allowing existing non-conforming rows to remain unchanged. Citus supports this feature for CHECK constraints and foreign keys, using PostgreSQL's "NOT VALID" constraint designation.

For example, consider an application which stores user profiles in a :ref:`reference table <reference_tables>`.

.. code-block:: postgres

   -- we're using the "text" column type here, but a real application
   -- might use "citext" which is available in a postgres contrib module

   CREATE TABLE users ( email text PRIMARY KEY );
   SELECT create_reference_table('users');

In the course of time imagine that a few non-addresses get into the table.

.. code-block:: postgres

   INSERT INTO users VALUES
      ('foo@example.com'), ('hacker12@aol.com'), ('lol');

We would like to validate the addresses, but PostgreSQL does not ordinarily allow us to add a CHECK constraint that fails for existing rows. However it *does* allow a constraint marked not valid:

.. code-block:: postgres

   ALTER TABLE users
   ADD CONSTRAINT syntactic_email
   CHECK (email ~
      '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
   ) NOT VALID;

This succeeds, and new rows are protected.

.. code-block:: postgres

   INSERT INTO users VALUES ('fake');

   /*
   ERROR:  new row for relation "users_102010" violates
           check constraint "syntactic_email_102010"
   DETAIL:  Failing row contains (fake).
   */

Later, during non-peak hours, a database administrator can attempt to fix the bad rows and re-validate the constraint.

.. code-block:: postgres

   -- later, attempt to validate all rows
   ALTER TABLE users
   VALIDATE CONSTRAINT syntactic_email;

The PostgreSQL documentation has more information about NOT VALID and VALIDATE CONSTRAINT in the `ALTER TABLE <https://www.postgresql.org/docs/current/sql-altertable.html>`_ section.

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

Currently other DDL commands are not auto-propagated, however you can propagate the changes manually. See :ref:`manual_prop`.
