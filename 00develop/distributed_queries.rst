SQL Reference
#############

.. _ddl:

Creating and Modifying Distributed Tables (DDL)
===============================================

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

Now queries such as one calculating tax for a shopping cart can join on the :code:`states` table with no network overhead.

In addition to distributing a table as a single replicated shard, the :code:`create_reference_table` UDF marks it as a reference table in the Citus metadata tables. Citus automatically performs two-phase commits (`2PC <https://en.wikipedia.org/wiki/Two-phase_commit_protocol>`_) for modifications to tables marked this way, which provides strong consistency guarantees.

If you have an existing distributed table which has a shard count of one, you can upgrade it to be a recognized reference table by running

.. code-block:: postgresql

  SELECT upgrade_to_reference_table('table_name');

For another example of using reference tables in a multi-tenant application, see :ref:`mt_ref_tables`.

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

This example shows how to create primary and foreign keys on distributed tables.

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

.. _dml:

Ingesting, Modifying Data (DML)
===============================

The following code snippets use the Github events example, see :ref:`ddl`.

Inserting Data
--------------

Single Row Inserts
~~~~~~~~~~~~~~~~~~

To insert data into distributed tables, you can use the standard PostgreSQL `INSERT <http://www.postgresql.org/docs/current/static/sql-insert.html>`_ commands. As an example, we pick two rows randomly from the Github Archive dataset.

::

    INSERT INTO github_events VALUES (2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13');

    INSERT INTO github_events VALUES (2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24');

When inserting rows into distributed tables, the distribution column of the row being inserted must be specified. Based on the distribution column, Citus determines the right shard to which the insert should be routed to. Then, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

Multi-Row Inserts
~~~~~~~~~~~~~~~~~

Sometimes it's convenient to put multiple insert statements together into a single insert of multiple rows. It can also be more efficient than making repeated database queries. For instance, the example from the previous section can be loaded all at once like this:

::

    INSERT INTO github_events VALUES (
      2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13'
      ), (
        2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24'
      );

Bulk Loading
~~~~~~~~~~~~

Sometimes, you may want to bulk load many rows together into your distributed tables. To bulk load data from a file, you can directly use `PostgreSQL's \\COPY command <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_.

First download our example github_events dataset by running:

.. code-block:: bash

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz


Then, you can copy the data using psql:

.. code-block:: psql

    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

.. _dist_agg:

Distributed Aggregations
~~~~~~~~~~~~~~~~~~~~~~~~

Applications like event data pipelines and real-time dashboards require sub-second queries on large volumes of data. One way to make these queries fast is by calculating and saving aggregates ahead of time. This is called "rolling up" the data and it avoids the cost of processing raw data at run-time. As an extra benefit, rolling up timeseries data into hourly or daily statistics can also save space. Old data may be deleted when its full details are no longer needed and aggregates suffice.

For example, here is a distributed table for tracking page views by url:

.. code-block:: postgresql

  CREATE TABLE page_views (
    site_id int,
    url text,
    host_ip inet,
    view_time timestamp default now(),

    PRIMARY KEY (site_id, url)
  );

  SELECT create_distributed_table('page_views', 'site_id');

Once the table is populated with data, we can run an aggregate query to count page views per URL per day, restricting to a given site and year.

.. code-block:: postgresql

  -- how many views per url per day on site 5?
  SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE site_id = 5 AND
      view_time >= date '2016-01-01' AND view_time < date '2017-01-01'
    GROUP BY view_time::date, site_id, url;

The setup described above works, but has two drawbacks. First, when you repeatedly execute the aggregate query, it must go over each related row and recompute the results for the entire data set. If you're using this query to render a dashboard, it's faster to save the aggregated results in a daily page views table and query that table. Second, storage costs will grow proportionally with data volumes and the length of queryable history. In practice, you may want to keep raw events for a short time period and look at historical graphs over a longer time window.

To receive those benefits, we can create a :code:`daily_page_views` table to store the daily statistics.

.. code-block:: postgresql

  CREATE TABLE daily_page_views (
    site_id int,
    day date,
    url text,
    view_count bigint,
    PRIMARY KEY (site_id, day, url)
  );

  SELECT create_distributed_table('daily_page_views', 'site_id');

In this example, we distributed both :code:`page_views` and :code:`daily_page_views` on the :code:`site_id` column. This ensures that data corresponding to a particular site will be :ref:`co-located <colocation>` on the same node. Keeping the two tables' rows together on each node minimizes network traffic between nodes and enables highly parallel execution.

Once we create this new distributed table, we can then run :code:`INSERT INTO ... SELECT` to roll up raw page views into the aggregated table. In the following, we aggregate page views each day. Citus users often wait for a certain time period after the end of day to run a query like this, to accommodate late arriving data.

.. code-block:: postgresql

  -- roll up yesterday's data
  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE view_time >= date '2017-01-01' AND view_time < date '2017-01-02'
    GROUP BY view_time::date, site_id, url;

  -- now the results are available right out of the table
  SELECT day, site_id, url, view_count
    FROM daily_page_views
    WHERE site_id = 5 AND
      day >= date '2016-01-01' AND day < date '2017-01-01';

It's worth noting that for :code:`INSERT INTO ... SELECT` to work on distributed tables, Citus requires the source and destination table to be co-located. In summary:

- The tables queried and inserted are distributed by analogous columns
- The select query includes the distribution column
- The insert statement includes the distribution column

The rollup query above aggregates data from the previous day and inserts it into :code:`daily_page_views`. Running the query once each day means that no rollup tables rows need to be updated, because the new day's data does not affect previous rows.

The situation changes when dealing with late arriving data, or running the rollup query more than once per day. If any new rows match days already in the rollup table, the matching counts should increase. PostgreSQL can handle this situation with "ON CONFLICT," which is its technique for doing `upserts <https://www.postgresql.org/docs/10/static/sql-insert.html#SQL-ON-CONFLICT>`_. Here is an example.

.. code-block:: postgresql

  -- roll up from a given date onward,
  -- updating daily page views when necessary
  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE view_time >= date '2017-01-01'
    GROUP BY view_time::date, site_id, url
    ON CONFLICT (day, url, site_id) DO UPDATE SET
      view_count = daily_page_views.view_count + EXCLUDED.view_count;

Updates and Deletion
--------------------

You can update or delete rows from your distributed tables using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/current/static/sql-update.html>`_ and `DELETE <http://www.postgresql.org/docs/current/static/sql-delete.html>`_ commands.

::

    DELETE FROM github_events
    WHERE repo_id IN (24509048, 24509049);

    UPDATE github_events
    SET event_public = TRUE
    WHERE (org->>'id')::int = 5430905;

When updates/deletes affect multiple shards as in the above example, Citus defaults to using a one-phase commit protocol. For greater safety you can enable two-phase commits by setting

.. code-block:: postgresql

  SET citus.multi_shard_commit_protocol = '2pc';

If an update or delete affects only a single shard then it runs within a single worker node. In this case enabling 2PC is unnecessary. This often happens when updates or deletes filter by a table's distribution column:

.. code-block:: postgresql

  -- since github_events is distributed by repo_id,
  -- this will execute in a single worker node

  DELETE FROM github_events
  WHERE repo_id = 206084;

Maximizing Write Performance
----------------------------

Both INSERT and UPDATE/DELETE statements can be scaled up to around 50,000 queries per second on large machines. However, to achieve this rate, you will need to use many parallel, long-lived connections and consider how to deal with locking. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.

.. _querying:

Querying Distributed Tables (SQL)
=================================

As discussed in the previous sections, Citus is an extension which extends the latest PostgreSQL for distributed execution. This means that you can use standard PostgreSQL `SELECT <http://www.postgresql.org/docs/current/static/sql-select.html>`_ queries on the Citus coordinator for querying. Citus will then parallelize the SELECT queries involving complex selections, groupings and orderings, and JOINs to speed up the query performance. At a high level, Citus partitions the SELECT query into smaller query fragments, assigns these query fragments to workers, oversees their execution, merges their results (and orders them if needed), and returns the final result to the user.

In the following sections, we discuss the different types of queries you can run using Citus.

.. _aggregate_functions:

Aggregate Functions
-------------------

Citus supports and parallelizes most aggregate functions supported by PostgreSQL. Citus's query planner transforms the aggregate into its commutative and associative form so it can be parallelized. In this process, the workers run an aggregation query on the shards and the coordinator then combines the results from the workers to produce the final output.

.. _count_distinct:

Count (Distinct) Aggregates
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus supports count(distinct) aggregates in several ways. If the count(distinct) aggregate is on the distribution column, Citus can directly push down the query to the workers. If not, Citus runs select distinct statements on each worker, and returns the list to the coordinator where it obtains the final count.

Note that transferring this data becomes slower when workers have a greater number of distinct items. This is especially true for queries containing multiple count(distinct) aggregates, e.g.:

.. code-block:: sql

  -- multiple distinct counts in one query tend to be slow
  SELECT count(distinct a), count(distinct b), count(distinct c)
  FROM table_abc;


For these kind of queries, the resulting select distinct statements on the workers essentially produce a cross-product of rows to be transferred to the coordinator.

For increased performance you can choose to make an approximate count instead. Follow the steps below:

1. Download and install the hll extension on all PostgreSQL instances (the coordinator and all the workers).

   Please visit the PostgreSQL hll `github repository <https://github.com/citusdata/postgresql-hll>`_ for specifics on obtaining the extension.

1. Create the hll extension on all the PostgreSQL instances

   ::

       CREATE EXTENSION hll;

3. Enable count distinct approximations by setting the Citus.count_distinct_error_rate configuration value. Lower values for this configuration setting are expected to give more accurate results but take more time for computation. We recommend setting this to 0.005.

   ::

       SET citus.count_distinct_error_rate to 0.005;

   After this step, count(distinct) aggregates automatically switch to using HLL, with no changes necessary to your queries. You should be able to run approximate count distinct queries on any column of the table.

HyperLogLog Column
$$$$$$$$$$$$$$$$$$

Certain users already store their data as HLL columns. In such cases, they can dynamically roll up those data by creating custom aggregates within Citus.

As an example, if you want to run the hll_union aggregate function on your data stored as hll, you can define an aggregate function like below :

::

    CREATE AGGREGATE sum (hll)
    (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
    );


You can then call sum(hll_column) to roll up those columns within the database. Please note that these custom aggregates need to be created both on the coordinator and the workers.

.. _limit_pushdown:

Limit Pushdown
---------------------

Citus also pushes down the limit clauses to the shards on the workers wherever possible to minimize the amount of data transferred across network.

However, in some cases, SELECT queries with LIMIT clauses may need to fetch all rows from each shard to generate exact results. For example, if the query requires ordering by the aggregate column, it would need results of that column from all shards to determine the final aggregate value. This reduces performance of the LIMIT clause due to high volume of network data transfer. In such cases, and where an approximation would produce meaningful results, Citus provides an option for network efficient approximate LIMIT clauses.

LIMIT approximations are disabled by default and can be enabled by setting the configuration parameter citus.limit_clause_row_fetch_count. On the basis of this configuration value, Citus will limit the number of rows returned by each task for aggregation on the coordinator. Due to this limit, the final results may be approximate. Increasing this limit will increase the accuracy of the final results, while still providing an upper bound on the number of rows pulled from the workers.

::

    SET citus.limit_clause_row_fetch_count to 10000;

Views on Distributed Tables
---------------------------

Citus supports all views on distributed tables. For an overview of views' syntax and features, see the PostgreSQL documentation for `CREATE VIEW <https://www.postgresql.org/docs/current/static/sql-createview.html>`_.

Note that some views cause a less efficient query plan than others. For more about detecting and improving poor view performance, see :ref:`subquery_perf`. (Views are treated internally as subqueries.)

Citus supports materialized views as well, and stores them as local tables on the coordinator node. Using them in distributed queries after materialization requires wrapping them in a subquery, a technique described in :ref:`join_local_dist`.

.. _joins:

Joins
-----

Citus supports equi-JOINs between any number of tables irrespective of their size and distribution method. The query planner chooses the optimal join method and join order based on how tables are distributed. It evaluates several possible join orders and creates a join plan which requires minimum data to be transferred across network.

Co-located joins
~~~~~~~~~~~~~~~~

When two tables are :ref:`co-located <colocation>` then they can be joined efficiently on their common distribution columns. A co-located join is the most efficient way to join two large distributed tables.

Internally, the Citus coordinator knows which shards of the co-located tables might match with shards of the other table by looking at the distribution column metadata. This allows Citus to prune away shard pairs which cannot produce matching join keys. The joins between remaining shard pairs are executed in parallel on the workers and then the results are returned to the coordinator.

.. note::

  Be sure that the tables are distributed into the same number of shards and that the distribution columns of each table have exactly matching types. Attempting to join on columns of slightly different types such as int and bigint can cause problems.

Reference table joins
~~~~~~~~~~~~~~~~~~~~~

:ref:`reference_tables` can be used as "dimension" tables to join efficiently with large "fact" tables. Because reference tables are replicated in full across all worker nodes, a reference join can be decomposed into local joins on each worker and performed in parallel. A reference join is like a more flexible version of a co-located join because reference tables aren't distributed on any particular column and are free to join on any of their columns.

.. _repartition_joins:

Repartition joins
~~~~~~~~~~~~~~~~~

In some cases, you may need to join two tables on columns other than the distribution column. For such cases, Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases the table(s) to be partitioned are determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, co-located joins are more efficient than repartition joins as repartition joins require shuffling of data. So, you should try to distribute your tables by the common join keys whenever possible.

.. _citus_query_processing:

Query Processing
================

A Citus cluster consists of a coordinator instance and multiple worker instances. The data is sharded and replicated on the workers while the coordinator stores metadata about these shards. All queries issued to the cluster are executed via the coordinator. The coordinator partitions the query into smaller query fragments where each query fragment can be run independently on a shard. The coordinator then assigns the query fragments to workers, oversees their execution, merges their results, and returns the final result to the user. The query processing architecture can be described in brief by the diagram below.

.. image:: ../images/citus-high-level-arch.png

Citus’s query processing pipeline involves the two components:

* **Distributed Query Planner and Executor**
* **PostgreSQL Planner and Executor**

We discuss them in greater detail in the subsequent sections.

.. _distributed_query_planner:

Distributed Query Planner
-------------------------

Citus’s distributed query planner takes in a SQL query and plans it for distributed execution.

For SELECT queries, the planner first creates a plan tree of the input query and transforms it into its commutative and associative form so it can be parallelized. It also applies several optimizations to ensure that the queries are executed in a scalable manner, and that network I/O is minimized.

Next, the planner breaks the query into two parts - the coordinator query which runs on the coordinator and the worker query fragments which run on individual shards on the workers. The planner then assigns these query fragments to the workers such that all their resources are used efficiently. After this step, the distributed query plan is passed on to the distributed executor for execution.

The planning process for key-value lookups on the distribution column or modification queries is slightly different as they hit exactly one shard. Once the planner receives an incoming query, it needs to decide the correct shard to which the query should be routed. To do this, it extracts the distribution column in the incoming row and looks up the metadata to determine the right shard for the query. Then, the planner rewrites the SQL of that command to reference the shard table instead of the original table. This re-written plan is then passed to the distributed executor.

.. _distributed_query_executor:

Distributed Query Executor
--------------------------

Citus’s distributed executors run distributed query plans and handle failures that occur during query execution. The executors connect to the workers, send the assigned tasks to them and oversee their execution. If the executor cannot assign a task to the designated worker or if a task execution fails, then the executor dynamically re-assigns the task to replicas on other workers. The executor processes only the failed query sub-tree, and not the entire query while handling failures.

Citus has three basic executor types: real time, router, and task tracker. It chooses which to use dynamically, depending on the structure of each query, and can use more than one at once for a single query, assigning different executors to different subqueries/CTEs as needed to support the SQL functionality. This process is recursive: if Citus cannot determine how to run a subquery then it examines sub-subqueries.

At a high level, the real-time executor is useful for handling simple key-value lookups and INSERT, UPDATE, and DELETE queries. The task tracker is better suited for larger SELECT queries, and the router executor for access data that is co-located in a single worker node.

The choice of executor for each query can be displayed by running PostgreSQL's `EXPLAIN <https://www.postgresql.org/docs/current/static/sql-explain.html>`_ command. This can be useful for debugging performance issues.

.. _realtime_executor:

Real-time Executor
~~~~~~~~~~~~~~~~~~~

The real-time executor is the default executor used by Citus. It is well suited for getting fast responses to queries involving filters, aggregations and co-located joins. The real time executor opens one connection per shard to the workers and sends all fragment queries to them. It then fetches the results from each fragment query, merges them, and gives the final results back to the user.

Since the real time executor maintains an open connection for each shard to which it sends queries, it may reach file descriptor / connection limits while dealing with high shard counts. In such cases, the real-time executor throttles on assigning more tasks to workers to avoid overwhelming them with too many tasks. One can typically increase the file descriptor limit on modern operating systems to avoid throttling, and change Citus configuration to use the real-time executor. But, that may not be ideal for efficient resource management while running complex queries. For queries that touch thousands of shards or require large table joins, you can use the task tracker executor.

Furthermore, when the real time executor detects simple INSERT, UPDATE or DELETE queries it assigns the incoming query to the worker which has the target shard. The query is then handled by the worker PostgreSQL server and the results are returned back to the user. In case a modification fails on a shard replica, the executor marks the corresponding shard replica as invalid in order to maintain data consistency.

.. _router_executor:

Router Executor
~~~~~~~~~~~~~~~

When all data required for a query is stored on a single node, Citus can route the entire query to the node and run it there. The result set is then relayed through the coordinator node back to the client. The router executor takes care of this type of execution.

Although Citus supports a large percentage of SQL functionality even for cross-node queries, the advantage of router execution is 100% SQL coverage. Queries executing inside a node are run in a full-featured PostgreSQL worker instance. The disadvantage of router execution is the reduced parallelism of executing a query using only one computer.

Task Tracker Executor
~~~~~~~~~~~~~~~~~~~~~~

The task tracker executor is well suited for long running, complex data warehousing queries. This executor opens only one connection per worker, and assigns all fragment queries to a task tracker daemon on the worker. The task tracker daemon then regularly schedules new tasks and sees through their completion. The executor on the coordinator regularly checks with these task trackers to see if their tasks completed.

Each task tracker daemon on the workers also makes sure to execute at most citus.max_running_tasks_per_node concurrently. This concurrency limit helps in avoiding disk I/O contention when queries are not served from memory. The task tracker executor is designed to efficiently handle complex queries which require repartitioning and shuffling intermediate data among workers.

.. _push_pull_execution:

Subquery/CTE Push-Pull Execution
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If necessary Citus can gather results from subqueries and CTEs into the coordinator node and then push them back across workers for use by an outer query. This allows Citus to support a greater variety of SQL constructs, and even mix executor types between a query and its subqueries.

For example, having subqueries in a WHERE clause sometimes cannot execute inline at the same time as the main query, but must be done separately. Suppose a web analytics application maintains a ``visits`` table partitioned by ``page_id``. To query the number of visitor sessions on the top twenty most visited pages, we can use a subquery to find the list of pages, then an outer query to count the sessions.

.. code-block:: sql

  SELECT page_id, count(distinct session_id)
  FROM visits
  WHERE page_id IN (
    SELECT page_id
    FROM visits
    GROUP BY page_id
    ORDER BY count(*) DESC
    LIMIT 20
  )
  GROUP BY page_id;

The real-time executor would like to run a fragment of this query against each shard by page_id, counting distinct session_ids, and combining the results on the coordinator. However the LIMIT in the subquery means the subquery cannot be executed as part of the fragment. By recursively planning the query Citus can run the subquery separately, push the results to all workers, run the main fragment query, and pull the results back to the coordinator. The "push-pull" design supports a subqueries like the one above.

Let's see this in action by reviewing the `EXPLAIN <https://www.postgresql.org/docs/current/static/sql-explain.html>`_ output for this query. It's fairly involved:

::

  GroupAggregate  (cost=0.00..0.00 rows=0 width=0)
    Group Key: remote_scan.page_id
    ->  Sort  (cost=0.00..0.00 rows=0 width=0)
      Sort Key: remote_scan.page_id
      ->  Custom Scan (Citus Real-Time)  (cost=0.00..0.00 rows=0 width=0)
        ->  Distributed Subplan 6_1
          ->  Limit  (cost=0.00..0.00 rows=0 width=0)
            ->  Sort  (cost=0.00..0.00 rows=0 width=0)
              Sort Key: COALESCE((pg_catalog.sum((COALESCE((pg_catalog.sum(remote_scan.worker_column_2))::bigint, '0'::bigint))))::bigint, '0'::bigint) DESC
              ->  HashAggregate  (cost=0.00..0.00 rows=0 width=0)
                Group Key: remote_scan.page_id
                ->  Custom Scan (Citus Real-Time)  (cost=0.00..0.00 rows=0 width=0)
                  Task Count: 32
                  Tasks Shown: One of 32
                  ->  Task
                    Node: host=localhost port=5433 dbname=postgres
                    ->  Limit  (cost=1883.00..1883.05 rows=20 width=12)
                      ->  Sort  (cost=1883.00..1965.54 rows=33017 width=12)
                        Sort Key: (count(*)) DESC
                        ->  HashAggregate  (cost=674.25..1004.42 rows=33017 width=12)
                          Group Key: page_id
                          ->  Seq Scan on visits_102264 visits  (cost=0.00..509.17 rows=33017 width=4)
        Task Count: 32
        Tasks Shown: One of 32
        ->  Task
          Node: host=localhost port=5433 dbname=postgres
          ->  HashAggregate  (cost=734.53..899.61 rows=16508 width=8)
            Group Key: visits.page_id, visits.session_id
            ->  Hash Join  (cost=17.00..651.99 rows=16508 width=8)
              Hash Cond: (visits.page_id = intermediate_result.page_id)
              ->  Seq Scan on visits_102264 visits  (cost=0.00..509.17 rows=33017 width=8)
              ->  Hash  (cost=14.50..14.50 rows=200 width=4)
                ->  HashAggregate  (cost=12.50..14.50 rows=200 width=4)
                  Group Key: intermediate_result.page_id
                  ->  Function Scan on read_intermediate_result intermediate_result  (cost=0.00..10.00 rows=1000 width=4)

Let's break it apart and examine each piece.

::

  GroupAggregate  (cost=0.00..0.00 rows=0 width=0)
    Group Key: remote_scan.page_id
    ->  Sort  (cost=0.00..0.00 rows=0 width=0)
      Sort Key: remote_scan.page_id

The root of the tree is what the coordinator node does with the results from the workers. In this case it is grouping them, and GroupAggregate requires they be sorted first.

::

      ->  Custom Scan (Citus Real-Time)  (cost=0.00..0.00 rows=0 width=0)
        ->  Distributed Subplan 6_1
  .

The custom scan has two large sub-trees, starting with a "distributed subplan."

::

          ->  Limit  (cost=0.00..0.00 rows=0 width=0)
            ->  Sort  (cost=0.00..0.00 rows=0 width=0)
              Sort Key: COALESCE((pg_catalog.sum((COALESCE((pg_catalog.sum(remote_scan.worker_column_2))::bigint, '0'::bigint))))::bigint, '0'::bigint) DESC
              ->  HashAggregate  (cost=0.00..0.00 rows=0 width=0)
                Group Key: remote_scan.page_id
                ->  Custom Scan (Citus Real-Time)  (cost=0.00..0.00 rows=0 width=0)
                  Task Count: 32
                  Tasks Shown: One of 32
                  ->  Task
                    Node: host=localhost port=5433 dbname=postgres
                    ->  Limit  (cost=1883.00..1883.05 rows=20 width=12)
                      ->  Sort  (cost=1883.00..1965.54 rows=33017 width=12)
                        Sort Key: (count(*)) DESC
                        ->  HashAggregate  (cost=674.25..1004.42 rows=33017 width=12)
                          Group Key: page_id
                          ->  Seq Scan on visits_102264 visits  (cost=0.00..509.17 rows=33017 width=4)
  .

Worker nodes run the above for each of the thirty-two shards (Citus is choosing one representative for display). We can recognize all the pieces of the ``IN (…)`` subquery: the sorting, grouping and limiting. When all workers have completed this query, they send their output back to the coordinator which puts it together as "intermediate results."

::

        Task Count: 32
        Tasks Shown: One of 32
        ->  Task
          Node: host=localhost port=5433 dbname=postgres
          ->  HashAggregate  (cost=734.53..899.61 rows=16508 width=8)
            Group Key: visits.page_id, visits.session_id
            ->  Hash Join  (cost=17.00..651.99 rows=16508 width=8)
              Hash Cond: (visits.page_id = intermediate_result.page_id)
  .

Citus starts another real-time job in this second subtree. It's going to count distinct sessions in visits. It uses a JOIN to connect with the intermediate results. The intermediate results will help it restrict to the top twenty pages.

::

              ->  Seq Scan on visits_102264 visits  (cost=0.00..509.17 rows=33017 width=8)
              ->  Hash  (cost=14.50..14.50 rows=200 width=4)
                ->  HashAggregate  (cost=12.50..14.50 rows=200 width=4)
                  Group Key: intermediate_result.page_id
                  ->  Function Scan on read_intermediate_result intermediate_result  (cost=0.00..10.00 rows=1000 width=4)
  .

The worker internally retrieves intermediate results using a ``read_intermediate_result`` function which loads data from a file that was copied in from the coordinator node.

This example showed how Citus executed the query in multiple steps with a distributed subplan, and how you can use EXPLAIN to learn about distributed query execution.

.. _postgresql_planner_executor:

PostgreSQL planner and executor
--------------------------------

Once the distributed executor sends the query fragments to the workers, they are processed like regular PostgreSQL queries. The PostgreSQL planner on that worker chooses the most optimal plan for executing that query locally on the corresponding shard table. The PostgreSQL executor then runs that query and returns the query results back to the distributed executor. You can learn more about the PostgreSQL `planner <http://www.postgresql.org/docs/current/static/planner-optimizer.html>`_ and `executor <http://www.postgresql.org/docs/current/static/executor.html>`_ from the PostgreSQL manual. Finally, the distributed executor passes the results to the coordinator for final aggregation.

Manual Query Propagation
========================

When the user issues a query, the Citus coordinator partitions it into smaller query fragments where each query fragment can be run independently on a worker shard. This allows Citus to distribute each query across the cluster.

However the way queries are partitioned into fragments (and which queries are propagated at all) varies by the type of query. In some advanced situations it is useful to manually control this behavior. Citus provides utility functions to propagate SQL to workers, shards, or placements.

Manual query propagation bypasses coordinator logic, locking, and any other consistency checks. These functions are available as a last resort to allow statements which Citus otherwise does not run natively. Use them carefully to avoid data inconsistency and deadlocks.

.. _worker_propagation:

Running on all Workers
----------------------

The least granular level of execution is broadcasting a statement for execution on all workers. This is useful for viewing properties of entire worker databases or creating UDFs uniformly throughout the cluster. For example:

.. code-block:: postgresql

  -- Make a UDF available on all workers
  SELECT run_command_on_workers($cmd$ CREATE FUNCTION ... $cmd$);

  -- List the work_mem setting of each worker database
  SELECT run_command_on_workers($cmd$ SHOW work_mem; $cmd$);

.. note::

  The :code:`run_command_on_workers` function and other manual propagation commands in this section can run only queries which return a single column and single row.

Running on all Shards
---------------------

The next level of granularity is running a command across all shards of a particular distributed table. It can be useful, for instance, in reading the properties of a table directly on workers. Queries run locally on a worker node have full access to metadata such as table statistics.

The :code:`run_command_on_shards` function applies a SQL command to each shard, where the shard name is provided for interpolation in the command. Here is an example of estimating the row count for a distributed table by using the pg_class table on each worker to estimate the number of rows for each shard. Notice the :code:`%s` which will be replaced with each shard's name.

.. code-block:: postgresql

  -- Get the estimated row count for a distributed table by summing the
  -- estimated counts of rows for each shard.
  SELECT sum(result::bigint) AS estimated_count
  FROM run_command_on_shards(
    'my_distributed_table',
    $cmd$
      SELECT reltuples
        FROM pg_class c
        JOIN pg_catalog.pg_namespace n on n.oid=c.relnamespace
       WHERE n.nspname||'.'||relname = '%s';
    $cmd$
  );

Running on all Placements
-------------------------

The most granular level of execution is running a command across all shards and their replicas (aka :ref:`placements <placements>`). It can be useful for running data modification commands, which must apply to every replica to ensure consistency.

For example, suppose a distributed table has an :code:`updated_at` field, and we want to "touch" all rows so that they are marked as updated at a certain time. An ordinary UPDATE statement on the coordinator requires a filter by the distribution column, but we can manually propagate the update across all shards and replicas:

.. code-block:: postgresql

  -- note we're using a hard-coded date rather than
  -- a function such as "now()" because the query will
  -- run at slightly different times on each replica

  SELECT run_command_on_placements(
    'my_distributed_table',
    $cmd$
      UPDATE %s SET updated_at = '2017-01-01';
    $cmd$
  );

A useful companion to :code:`run_command_on_placements` is :code:`run_command_on_colocated_placements`. It interpolates the names of *two* placements of :ref:`co-located <colocation>` distributed tables into a query. The placement pairs are always chosen to be local to the same worker where full SQL coverage is available. Thus we can use advanced SQL features like triggers to relate the tables:

.. code-block:: postgresql

  -- Suppose we have two distributed tables
  CREATE TABLE little_vals (key int, val int);
  CREATE TABLE big_vals    (key int, val int);
  SELECT create_distributed_table('little_vals', 'key');
  SELECT create_distributed_table('big_vals',    'key');

  -- We want to synchronise them so that every time little_vals
  -- are created, big_vals appear with double the value
  --
  -- First we make a trigger function on each worker, which will
  -- take the destination table placement as an argument
  SELECT run_command_on_workers($cmd$
    CREATE OR REPLACE FUNCTION embiggen() RETURNS TRIGGER AS $$
      BEGIN
        IF (TG_OP = 'INSERT') THEN
          EXECUTE format(
            'INSERT INTO %s (key, val) SELECT ($1).key, ($1).val*2;',
            TG_ARGV[0]
          ) USING NEW;
        END IF;
        RETURN NULL;
      END;
    $$ LANGUAGE plpgsql;
  $cmd$);

  -- Next we relate the co-located tables by the trigger function
  -- on each co-located placement
  SELECT run_command_on_colocated_placements(
    'little_vals',
    'big_vals',
    $cmd$
      CREATE TRIGGER after_insert AFTER INSERT ON %s
        FOR EACH ROW EXECUTE PROCEDURE embiggen(%s)
    $cmd$
  );

Limitations
-----------

* There are no safe-guards against deadlock for multi-statement transactions.
* There are no safe-guards against mid-query failures and resulting inconsistencies.
* Query results are cached in memory; these functions can't deal with very big result sets.
* The functions error out early if they cannot connect to a node.
* You can do very bad things!

.. _citus_sql_reference:

SQL Support and Workarounds
===========================

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus supports all SQL queries on distributed tables, with only these exceptions:

* Correlated subqueries
* `Recursive <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_/`modifying <https://www.postgresql.org/docs/current/static/queries-with.html#QUERIES-WITH-MODIFYING>`_ CTEs
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_
* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_
* `Window functions <https://www.postgresql.org/docs/current/static/tutorial-window.html>`_ that do not include the distribution column in PARTITION BY

Furthermore, in :ref:`mt_use_case` when queries are filtered by table :ref:`dist_column` to a single tenant then all SQL features work, including the ones above.

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.

.. _workarounds:

Workarounds
-----------

Before attempting workarounds consider whether Citus is appropriate for your
situation. Citus' current version works well for :ref:`real-time analytics and
multi-tenant use cases. <when_to_use_citus>`

Citus supports all SQL statements in the multi-tenant use-case. Even in the real-time analytics use-cases, with queries that span across nodes, Citus supports the majority of statements. The few types of unsupported queries are listed in :ref:`unsupported` Many of the unsupported features have workarounds; below are a number of the most useful.

.. _join_local_dist:

JOIN a local and a distributed table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Attempting to execute a JOIN between a local table "local" and a distributed table "dist" causes an error:

.. code-block:: sql

  SELECT * FROM local JOIN dist USING (id);

  /*
  ERROR:  relation local is not distributed
  STATEMENT:  SELECT * FROM local JOIN dist USING (id);
  ERROR:  XX000: relation local is not distributed
  LOCATION:  DistributedTableCacheEntry, metadata_cache.c:711
  */

Although you can't join such tables directly, by wrapping the local table in a subquery or CTE you can make Citus' recursive query planner copy the local table data to worker nodes. By colocating the data this allows the query to proceed.

.. code-block:: sql

  -- either

  SELECT *
    FROM (SELECT * FROM local) AS x
    JOIN dist USING (id);

  -- or

  WITH x AS (SELECT * FROM local)
  SELECT * FROM x
  JOIN dist USING (id);

Remember that the coordinator will send the results in the subquery or CTE to all workers which require it for processing. Thus it's best to either add the most specific filters and limits to the inner query as possible, or else aggregate the table. That reduces the network overhead which such a query can cause. More about this in :ref:`subquery_perf`.

Temp Tables: the Last Resort
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are still a few queries that are :ref:`unsupported <unsupported>` even with the use of push-pull execution via subqueries. One of them is running window functions that partition by a non-distribution column.

Suppose we have a table called :code:`github_events`, distributed by the column :code:`user_id`. Then the following window function will not work:

.. code-block:: sql

  -- this won't work

  SELECT repo_id, org->'id' as org_id, count(*)
    OVER (PARTITION BY repo_id) -- repo_id is not distribution column
    FROM github_events
   WHERE repo_id IN (8514, 15435, 19438, 21692);

There is another trick though. We can pull the relevant information to the coordinator as a temporary table:

.. code-block:: sql

  -- grab the data, minus the aggregate, into a local table

  CREATE TEMP TABLE results AS (
    SELECT repo_id, org->'id' as org_id
      FROM github_events
     WHERE repo_id IN (8514, 15435, 19438, 21692)
  );

  -- now run the aggregate locally

  SELECT repo_id, org_id, count(*)
    OVER (PARTITION BY repo_id)
    FROM results;

Creating a temporary table on the coordinator is a last resort. It is limited by the disk size and CPU of the node.
