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

These functions are analogous to three of the standard PostgreSQL `object size functions <https://www.postgresql.org/docs/current/static/functions-admin.html#FUNCTIONS-ADMIN-DBSIZE>`_, with the additional note that if they can't connect to a node, they error out.

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

Usage
-----

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

You can also convert between row-based (heap) and columnar storage.

.. code-block:: postgresql

    -- Convert to row-based (heap) storage
    SELECT alter_table_set_access_method('contestant', 'heap');

    -- Convert to columnar storage (indexes will be dropped)
    SELECT alter_table_set_access_method('contestant', 'columnar');

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
contain the same data, and compare.

Measuring compression
---------------------

Let's create a new example with more data to benchmark the compression savings.

.. code-block:: postgresql

    -- first a wide table using row storage
    CREATE TABLE perf_row(
      c00 int8, c01 int8, c02 int8, c03 int8, c04 int8, c05 int8, c06 int8, c07 int8, c08 int8, c09 int8,
      c10 int8, c11 int8, c12 int8, c13 int8, c14 int8, c15 int8, c16 int8, c17 int8, c18 int8, c19 int8,
      c20 int8, c21 int8, c22 int8, c23 int8, c24 int8, c25 int8, c26 int8, c27 int8, c28 int8, c29 int8,
      c30 int8, c31 int8, c32 int8, c33 int8, c34 int8, c35 int8, c36 int8, c37 int8, c38 int8, c39 int8,
      c40 int8, c41 int8, c42 int8, c43 int8, c44 int8, c45 int8, c46 int8, c47 int8, c48 int8, c49 int8,
      c50 int8, c51 int8, c52 int8, c53 int8, c54 int8, c55 int8, c56 int8, c57 int8, c58 int8, c59 int8,
      c60 int8, c61 int8, c62 int8, c63 int8, c64 int8, c65 int8, c66 int8, c67 int8, c68 int8, c69 int8,
      c70 int8, c71 int8, c72 int8, c73 int8, c74 int8, c75 int8, c76 int8, c77 int8, c78 int8, c79 int8,
      c80 int8, c81 int8, c82 int8, c83 int8, c84 int8, c85 int8, c86 int8, c87 int8, c88 int8, c89 int8,
      c90 int8, c91 int8, c92 int8, c93 int8, c94 int8, c95 int8, c96 int8, c97 int8, c98 int8, c99 int8
    );
    
    -- next a table with identical columns using columnar storage
    CREATE TABLE perf_columnar(LIKE perf_row) USING COLUMNAR;

Fill both tables with the same large dataset:

.. code-block:: postgresql

    INSERT INTO perf_row
      SELECT
        g % 00500, g % 01000, g % 01500, g % 02000, g % 02500, g % 03000, g % 03500, g % 04000, g % 04500, g % 05000,
        g % 05500, g % 06000, g % 06500, g % 07000, g % 07500, g % 08000, g % 08500, g % 09000, g % 09500, g % 10000,
        g % 10500, g % 11000, g % 11500, g % 12000, g % 12500, g % 13000, g % 13500, g % 14000, g % 14500, g % 15000,
        g % 15500, g % 16000, g % 16500, g % 17000, g % 17500, g % 18000, g % 18500, g % 19000, g % 19500, g % 20000,
        g % 20500, g % 21000, g % 21500, g % 22000, g % 22500, g % 23000, g % 23500, g % 24000, g % 24500, g % 25000,
        g % 25500, g % 26000, g % 26500, g % 27000, g % 27500, g % 28000, g % 28500, g % 29000, g % 29500, g % 30000,
        g % 30500, g % 31000, g % 31500, g % 32000, g % 32500, g % 33000, g % 33500, g % 34000, g % 34500, g % 35000,
        g % 35500, g % 36000, g % 36500, g % 37000, g % 37500, g % 38000, g % 38500, g % 39000, g % 39500, g % 40000,
        g % 40500, g % 41000, g % 41500, g % 42000, g % 42500, g % 43000, g % 43500, g % 44000, g % 44500, g % 45000,
        g % 45500, g % 46000, g % 46500, g % 47000, g % 47500, g % 48000, g % 48500, g % 49000, g % 49500, g % 50000
      FROM generate_series(1,50000000) g;
    
    INSERT INTO perf_columnar
      SELECT
        g % 00500, g % 01000, g % 01500, g % 02000, g % 02500, g % 03000, g % 03500, g % 04000, g % 04500, g % 05000,
        g % 05500, g % 06000, g % 06500, g % 07000, g % 07500, g % 08000, g % 08500, g % 09000, g % 09500, g % 10000,
        g % 10500, g % 11000, g % 11500, g % 12000, g % 12500, g % 13000, g % 13500, g % 14000, g % 14500, g % 15000,
        g % 15500, g % 16000, g % 16500, g % 17000, g % 17500, g % 18000, g % 18500, g % 19000, g % 19500, g % 20000,
        g % 20500, g % 21000, g % 21500, g % 22000, g % 22500, g % 23000, g % 23500, g % 24000, g % 24500, g % 25000,
        g % 25500, g % 26000, g % 26500, g % 27000, g % 27500, g % 28000, g % 28500, g % 29000, g % 29500, g % 30000,
        g % 30500, g % 31000, g % 31500, g % 32000, g % 32500, g % 33000, g % 33500, g % 34000, g % 34500, g % 35000,
        g % 35500, g % 36000, g % 36500, g % 37000, g % 37500, g % 38000, g % 38500, g % 39000, g % 39500, g % 40000,
        g % 40500, g % 41000, g % 41500, g % 42000, g % 42500, g % 43000, g % 43500, g % 44000, g % 44500, g % 45000,
        g % 45500, g % 46000, g % 46500, g % 47000, g % 47500, g % 48000, g % 48500, g % 49000, g % 49500, g % 50000
      FROM generate_series(1,50000000) g;
    
    VACUUM (FREEZE, ANALYZE) perf_row;
    VACUUM (FREEZE, ANALYZE) perf_columnar;

For this data, you can see a compression ratio of better than 8X in the columnar table.

.. code-block:: postgresql

    SELECT pg_total_relation_size('perf_row')::numeric/
           pg_total_relation_size('perf_columnar') AS compression_ratio;

::

    .
     compression_ratio
    --------------------
     8.0196135873627944
    (1 row)

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
* Support for hash and btree indices only
* No index scans, or bitmap index scans
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
