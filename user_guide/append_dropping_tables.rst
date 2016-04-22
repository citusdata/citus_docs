.. _append_dropping_tables:

Dropping Tables
###############
CitusDB users can use the standard PostgreSQL `DROP TABLE <http://www.postgresql.org/docs/9.4/static/sql-droptable.html>`_
command to remove their append distributed tables. As with regular tables, DROP TABLE removes any
indexes, rules, triggers, and constraints that exist for the target table.

Please note that this only removes the table's metadata, but doesn't delete the
table's shards from the worker nodes. If you wants to drop the shards before
removing the table, you can first delete all shards using the
:ref:`master_apply_delete_command UDF <append_dropping_shards>` as discussed in the previous section and then issue the DROP table
command.


::

    DROP TABLE github_events CASCADE ;
    NOTICE:  drop cascades to distribute by append
    NOTICE:  removing only metadata for the distributed table
    DETAIL:  shards for this table are not removed
    DROP TABLE

