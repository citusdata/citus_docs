Table Management
$$$$$$$$$$$$$$$$$$

.. _rls:

Row-Level Security
##################

.. note::

  Row-level security support is a part of Citus Enterprise. Please `contact us <https://www.citusdata.com/about/contact_us>`_ to obtain this functionality.

PostgreSQL `row-level security <https://www.postgresql.org/docs/current/static/ddl-rowsecurity.html>`_ policies restrict, on a per-user basis, which rows can be returned by normal queries or inserted, updated, or deleted by data modification commands. This can be especially useful in a multi-tenant Citus cluster because it allows individual tenants to have full SQL access to the database while hiding each tenant's information from other tenants.

We can implement the separation of tenant data by using a naming convention for database roles that ties into table row-level security policies. We'll assign each tenant a database role in a numbered sequence: ``tenant_1``, ``tenant_2``, etc. Tenants will connect to Citus using these separate roles. Row-level security policies can compare the role name to values in the ``tenant_id`` distribution column to decide whether to allow access.

Here is how to apply the approach on a simplified events table distributed by ``tenant_id``. First create the roles ``tenant_1`` and ``tenant_2`` (it's easy on Citus Cloud, see :ref:`cloud_roles`). Then run the following as an administrator:

.. code-block:: sql

  CREATE TABLE events(
    tenant_id int,
    id int,
    type text
  );

  SELECT create_distributed_table('events','tenant_id');

  INSERT INTO events VALUES (1,1,'foo'), (2,2,'bar');

  -- assumes that roles tenant_1 and tenant_2 exist
  GRANT select, update, insert, delete
    ON events TO tenant_1, tenant_2;

As it stands, anyone with select permissions for this table can see both rows. Users from either tenant can see and update the row of the other tenant. We can solve this with row-level table security policies.

Each policy consists of two clauses: USING and WITH CHECK. When a user tries to read or write rows, the database evaluates each row against these clauses. Existing table rows are checked against the expression specified in USING, while new rows that would be created via INSERT or UPDATE are checked against the expression specified in WITH CHECK.

.. code-block:: postgresql

  -- first a policy for the system admin "citus" user
  CREATE POLICY admin_all ON events
    TO citus           -- apply to this role
    USING (true)       -- read any existing row
    WITH CHECK (true); -- insert or update any row

  -- next a policy which allows role "tenant_<n>" to
  -- access rows where tenant_id = <n>
  CREATE POLICY user_mod ON events
    USING (current_user = 'tenant_' || tenant_id::text);
    -- lack of CHECK means same condition as USING

  -- enforce the policies
  ALTER TABLE events ENABLE ROW LEVEL SECURITY;

Now roles ``tenant_1`` and ``tenant_2`` get different results for their queries:

**Connected as tenant_1:**

.. code-block:: sql

  SELECT * FROM events;

::

  ┌───────────┬────┬──────┐
  │ tenant_id │ id │ type │
  ├───────────┼────┼──────┤
  │         1 │  1 │ foo  │
  └───────────┴────┴──────┘

**Connected as tenant_2:**

.. code-block:: sql

  SELECT * FROM events;

::

  ┌───────────┬────┬──────┐
  │ tenant_id │ id │ type │
  ├───────────┼────┼──────┤
  │         2 │  2 │ bar  │
  └───────────┴────┴──────┘

.. code-block:: sql

  INSERT INTO events VALUES (3,3,'surprise');
  /*
  ERROR:  42501: new row violates row-level security policy for table "events_102055"
  */

.. _table_size:

Determining Table and Relation Size
###################################

The usual way to find table sizes in PostgreSQL, :code:`pg_total_relation_size`, drastically under-reports the size of distributed tables. All this function does on a Citus cluster is reveal the size of tables on the coordinator node. In reality the data in distributed tables lives on the worker nodes (in shards), not on the coordinator. A true measure of distributed table size is obtained as a sum of shard sizes. Citus provides helper functions to query this information.

+------------------------------------------+---------------------------------------------------------------+
| UDF                                      | Returns                                                       |
+==========================================+===============================================================+
| citus_relation_size(relation_name)       | * Size of actual data in table (the "`main fork <forks_>`_"). |
|                                          |                                                               |
|                                          | * A relation can be the name of a table or an index.          |
+------------------------------------------+---------------------------------------------------------------+
| citus_table_size(relation_name)          | * citus_relation_size plus:                                   |
|                                          |                                                               |
|                                          |    * size of `free space map <freemap_>`_                     |
|                                          |    * size of `visibility map <vismap_>`_                      |
+------------------------------------------+---------------------------------------------------------------+
| citus_total_relation_size(relation_name) | * citus_table_size plus:                                      |
|                                          |                                                               |
|                                          |    * size of indices                                          |
+------------------------------------------+---------------------------------------------------------------+

These functions are analogous to three of the standard PostgreSQL `object size functions <https://www.postgresql.org/docs/current/static/functions-admin.html#FUNCTIONS-ADMIN-DBSIZE>`_, with the additional note that

* They work only when :code:`citus.shard_replication_factor` = 1.
* If they can't connect to a node, they error out.

Here is an example of using one of the helper functions to list the sizes of all distributed tables:

.. code-block:: postgresql

  SELECT logicalrelid AS name,
         pg_size_pretty(citus_table_size(logicalrelid)) AS size
    FROM pg_dist_partition;

Output:

::

  ┌───────────────┬───────┐
  │     name      │ size  │
  ├───────────────┼───────┤
  │ github_users  │ 39 MB │
  │ github_events │ 37 MB │
  └───────────────┴───────┘

Vacuuming Distributed Tables
############################

In PostgreSQL (and other MVCC databases), an UPDATE or DELETE of a row does not immediately remove the old version of the row. The accumulation of outdated rows is called bloat and must be cleaned to avoid decreased query performance and unbounded growth of disk space requirements. PostgreSQL runs a process called the auto-vacuum daemon that periodically vacuums (aka removes) outdated rows.

It’s not just user queries which scale in a distributed database, vacuuming does too. In PostgreSQL big busy tables have great potential to bloat, both from lower sensitivity to PostgreSQL's vacuum scale factor parameter, and generally because of the extent of their row churn. Splitting a table into distributed shards means both that individual shards are smaller tables and that auto-vacuum workers can parallelize over different parts of the table on different machines. Ordinarily auto-vacuum can only run one worker per table.

Due to the above, auto-vacuum operations on a Citus cluster are probably good enough for most cases. However for tables with particular workloads, or companies with certain "safe" hours to schedule a vacuum, it might make more sense to manually vacuum a table rather than leaving all the work to auto-vacuum.

To vacuum a table, simply run this on the coordinator node:

.. code-block:: postgresql

  VACUUM my_distributed_table;

Using vacuum against a distributed table will send a vacuum command to every one of that table's placements (one connection per placement). This is done in parallel. All `options <https://www.postgresql.org/docs/current/static/sql-vacuum.html>`_ are supported (including the :code:`column_list` parameter) except for :code:`VERBOSE`. The vacuum command also runs on the coordinator, and does so before any workers nodes are notified. Note that unqualified vacuum commands (i.e. those without a table specified) do not propagate to worker nodes.

Analyzing Distributed Tables
############################

PostgreSQL's ANALYZE command collects statistics about the contents of tables in the database. Subsequently, the query planner uses these statistics to help determine the most efficient execution plans for queries.

The auto-vacuum daemon, discussed in the previous section, will automatically issue ANALYZE commands whenever the content of a table has changed sufficiently. The daemon schedules ANALYZE strictly as a function of the number of rows inserted or updated; it has no knowledge of whether that will lead to meaningful statistical changes. Administrators might prefer to manually schedule ANALYZE operations instead, to coincide with statistically meaningful table changes.

To analyze a table, run this on the coordinator node:

.. code-block:: postgresql

  ANALYZE my_distributed_table;

Citus propagates the ANALYZE command to all worker node placements.

.. _freemap: https://www.postgresql.org/docs/current/static/storage-fsm.html
.. _vismap: https://www.postgresql.org/docs/current/static/storage-vm.html
.. _forks: https://www.postgresql.org/docs/current/static/storage-file-layout.html
