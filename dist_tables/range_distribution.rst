.. _range_distribution:

Range Distribution (Manual)
############################

Citus also supports range based distribution, but this currently requires manual effort to set up. In this section, we briefly describe how you can set up range distribution and where it can be useful.

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:
    
    ::
        
        export PATH=/usr/lib/postgresql/9.5/:$PATH

To create a range distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.5/static/sql-createtable.html>`_ statement in the same way as you would do with a regular postgresql table.

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

Next, you can use the master_create_distributed_table() function to mark the table as a range distributed table and specify its distribution column.

::

    SELECT master_create_distributed_table('github_events', 'created_at', 'range');

This function informs Citus that the github_events table should be distributed by range on the created_at column.

Range distribution signifies to the database that all the shards have
non-overlapping ranges of the distribution key. Currently, the \\copy command
for data loading expects that shard's have been created with non-overlapping
ranges, and cover the range of values expected in the file.

For example, with the above use-case, you would first create shards using
'master_create_empty_shard' for each day. Then, you would have to update the shard min
and max values manually for that day, and \\COPY would then be able to load the
data for the day. If \\COPY encounters a partition-column value which isn't
covered by an existing shard, it will throw an error.

The difference between range and append methods is that Citus’s distributed query planner has extra knowledge that the shards have distinct non-overlapping distribution key ranges. This allows the planner to push down more operations to the workers so that they can be executed in parallel. This reduces both the amount of data transferred across network and the amount of computation to be done for aggregation on the master.

If you want more specific details on how to set up range partitioning, please get in touch with us via
our mailing-list.

