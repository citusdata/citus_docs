Table Management
$$$$$$$$$$$$$$$$$$

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

Due to the above, auto-vacuum operations on a Citus cluster are probably good enough for most cases. However, for tables with particular workloads, or companies with certain "safe" hours to schedule a vacuum, it might make more sense to manually vacuum a table rather than leaving all the work to auto-vacuum.

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

.. _columnar:

Columnar Storage
################

Citus 10 introduces append-only columnar table storage for analytic and data
warehousing workloads. When columns (rather than rows) are stored contiguously
on disk, data becomes more compressible, and queries can request a subset of
columns more quickly.

To use columnar storage, specify ``USING columnar`` when creating a table:

.. code-block:: postgresql

  CREATE TABLE contestant (
      handle TEXT,
      birthdate DATE,
      rating INT,
      percentile FLOAT,
      country CHAR(3),
      achievements TEXT[]
  ) USING columnar;

Citus converts rows to columnar storage in "stripes" during insertion. Each
stripe holds one transaction's worth of data, or 150000 rows, whichever is
less.  (The stripe size and other parameters of a columnar table can be changed
with the :ref:`alter_columnar_table_set` function.)

For example, the following statement puts all five rows into the same stripe,
because all values are inserted in a single transaction:

.. code-block:: postgresql

  -- insert these values into a single columnar stripe

  INSERT INTO contestant VALUES
    ('a','1990-01-10',2090,97.1,'XA','{a}'),
    ('b','1990-11-01',2203,98.1,'XA','{a,b}'),
    ('c','1988-11-01',2907,99.4,'XB','{w,y}'),
    ('d','1985-05-05',2314,98.3,'XB','{}'),
    ('e','1995-05-05',2236,98.2,'XC','{a}');

It's best to make large stripes when possible, because Citus compresses
columnar data separately per stripe. We can see facts about our columnar table
like compression rate, number of stripes, and average rows per stripe by using
`VACUUM VERBOSE`:

.. code-block:: postgresql

  VACUUM VERBOSE contestant;

::

  INFO:  statistics for "contestant":
  storage id: 10000000000
  total file size: 24576, total data size: 248
  compression rate: 1.31x
  total row count: 5, stripe count: 1, average rows per stripe: 5
  chunk count: 6, containing data for dropped columns: 0, zstd compressed: 6

The output shows that Citus used the zstd compression algorithm to obtain 1.31x
data compression. The compression rate compares a) the size of inserted data as
it was staged in memory against b) the size of that data compressed in its
eventual stripe.

Because of how it's measured, the compression rate may or may not match the
size difference between row and columnar storage for a table. The only way
truly find that difference is to construct a row and columnar table that
contain the same data, and compare:

.. code-block:: postgresql

  CREATE TABLE contestant_row AS
      SELECT * FROM contestant;

  SELECT pg_total_relation_size('contestant_row') as row_size,
         pg_total_relation_size('contestant') as columnar_size;

::

  .
   row_size | columnar_size
  ----------+---------------
      16384 |         24576

For our tiny table the columnar storage actually uses more space, but as the
data grows, compression will win.

Example
-------

Columnar storage works well with table partitioning. For an example, see
:ref:`columnar_example`.

Gotchas
-------

* Columnar storage compresses per stripe. Stripes are created per transaction,
  so inserting one row per transaction will put single rows into their own
  stripes. Compression and performance of single row stripes will be worse than
  a row table. Always insert in bulk to a columnar table.
* If you mess up and columnarize a bunch of tiny stripes, there is no way to
  repair the table. The only fix is to create a new columnar table and copy
  data from the original in one transaction:

  .. code-block:: postgresql

    BEGIN;
    CREATE TABLE foo_compacted (LIKE foo) USING columnar;
    INSERT INTO foo_compacted SELECT * FROM foo;
    DROP TABLE foo;
    ALTER TABLE foo_compacted RENAME TO foo;
    COMMIT;

* Fundamentally non-compressible data can be a problem, although it can still
  be useful to use columnar so that less is loaded into memory when selecting
  specific columns.
* On a partitioned table with a mix of row and column partitions, updates must
  be carefully targeted or filtered to hit only the row partitions.

   * If the operation is targeted at a specific row partition (e.g. `UPDATE p2
     SET i = i + 1`), it will succeed; if targeted at a specified columnar
     partition (e.g. `UPDATE p1 SET i = i + 1`), it will fail.
   * If the operation is targeted at the partitioned table and has a WHERE
     clause that excludes all columnar partitions (e.g. `UPDATE parent SET i = i
     + 1 WHERE timestamp = '2020-03-15'`), it will succeed.
   * If the operation is targeted at the partitioned table, but does not
     exclude all columnar partitions, it will fail; even if the actual data to
     be updated only affects row tables (e.g. `UPDATE parent SET i = i + 1 WHERE
     n = 300`).

Limitations
-----------

Future versions of Citus will incrementally lift the current limitations:

* Append-only (no UPDATE/DELETE support)
* No space reclamation (e.g. rolled-back transactions may still consume disk space)
* No index support, index scans, or bitmap index scans
* No tidscans
* No sample scans
* No TOAST support (large values supported inline)
* No support for ON CONFLICT statements (except DO NOTHING actions with no target specified).
* No support for tuple locks (SELECT ... FOR SHARE, SELECT ... FOR UPDATE)
* No support for serializable isolation level
* Support for PostgreSQL server versions 12+ only
* No support for foreign keys, unique constraints, or exclusion constraints
* No support for logical decoding
* No support for intra-node parallel scans
* No support for AFTER ... FOR EACH ROW triggers
* No UNLOGGED columnar tables
* No TEMPORARY columnar tables
