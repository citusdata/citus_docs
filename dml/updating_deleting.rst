.. _general:

General Purpose Updates
-----------------------

The most flexible way to modify or delete rows throughout a Citus cluster is the master_modify_multiple_shards command. It takes a regular SQL statement as argument and runs it on all workers:

::

  SELECT master_modify_multiple_shards(
    'DELETE FROM customer_delete_protocol WHERE c_custkey > 500 AND c_custkey < 500');

This uses a two-phase commit to remove or update data safely everywhere.

.. _expiration:

Data Expiration
-------------------

A more specific type of deletion is that of removing old rows from an append-partitioned table. For example, removing events older than a given date.

::

  SELECT * from master_apply_delete_command(
    'DELETE FROM github_events WHERE review_date < ''2009-03-01''');

The master_apply_delete_command function requires a SQL statement containing a partition column in the where clause. It searches for any shards which fall entirely within the where clause condition and drops them. A shard which has any rows not covered in the range will be preserved. Hence this function is only approximate because some rows matching the where clause may survive. The use case for this function is to keep database size under control over time.
