.. _append_dropping_shards:

Dropping Shards
###############


In append distribution, users typically want to track data only for the last few months / years. In such cases, the shards that are no longer needed still occupy disk space. To address this, CitusDB provides a user defined function master_apply_delete_command() to delete old shards. The function takes a `DELETE <http://www.postgresql.org/docs/9.4/static/sql-delete.html>`_ command as input and deletes all the shards that match the delete criteria with their metadata.

The function uses shard metadata to decide whether or not a shard needs to be deleted, so it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards are selected for deletion. The UDF then connects to the worker nodes and issues DROP commands for all the shards which need to be deleted. If a drop query for a particular shard replica fails, then that replica is marked as TO DELETE. The shard replicas which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

Please note that this function only deletes complete shards and not individual rows from shards. If your use case requires deletion of individual rows in real-time, please consider using the hash distribution method.

The example below deletes those shards from the github_events table which have all rows with created_at <= '2014-01-01 00:00:00'. Note that the table is distributed on the created_at column.

::

    SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE created_at <= ''2014-01-01 00:00:00''');
     master_apply_delete_command
    -----------------------------
                               3
    (1 row)

To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.
