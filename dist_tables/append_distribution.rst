.. _append_distribution:

Append Distribution
###################

Append distributed tables are best suited to append-only event data
which arrives in a time-ordered series. In the next few sections, we describe how
users can create append distributed tables, load data into them and also expire
old data from them.

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:
    
    ::
        
        export PATH=/usr/lib/postgresql/9.5/:$PATH


We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::
    
    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Creating and Distributing Tables
---------------------------------

To create an append distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.5/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

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

Next, you can use the master_create_distributed_table() function to mark the table as an append distributed table and specify its distribution column.

::

    SELECT master_create_distributed_table('github_events', 'created_at', 'append');

This function informs Citus that the github_events table should be distributed by append on the created_at column. Note that this method doesn't enforce a particular distribution; it merely tells the database to keep minimum and maximum values for the created_at column in each shard which are later used by the database for optimizing queries.

Data Loading
------------

Citus supports two methods to load data into your append distributed tables. The first one is suitable for bulk loads from files and involves using the \\copy command. For use cases requiring smaller, incremental data loads, Citus provides two user defined functions. We describe each of the methods and their usage below.

Bulk load using \\copy
$$$$$$$$$$$$$$$$$$$$$$$

The `\\copy <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_
command is used to copy data from a file to a distributed table while handling
replication and failures automatically. You can also use the server side `COPY command <http://www.postgresql.org/docs/current/static/sql-copy.html>`_. 
In the examples, we use the \\copy command from psql, which sends a COPY .. FROM STDIN to the server and reads files on the client side, whereas COPY from a file would read the file on the server.

You can use \\copy both on the master and from any of the workers. When using it from the worker, you need to add the master_host option. Behind the scenes, \\copy first opens a connection to the master using the provided master_host option and uses master_create_empty_shard to create a new shard. Then, the command connects to the workers and copies data into the replicas until the size reaches shard_max_size, at which point another new shard is created. Finally, the command fetches statistics for the shards and updates the metadata.

::

    SET citus.shard_max_size TO '64MB';
    \copy github_events from 'github_events-2015-01-01-0.csv' WITH (format CSV, master_host 'master-host-101')

Citus assigns a unique shard id to each new shard and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. One can connect to the worker postgres instances to view or run commands on individual shards.

By default, the \\copy command depends on two configuration parameters for its behavior. These are called citus.shard_max_size and citus.shard_replication_factor.

(1) **citus.shard_max_size :-** This parameter determines the maximum size of a shard created using \\copy, and defaults to 1 GB. If the file is larger than this parameter, \\copy will break it up into multiple shards.
(2) **citus.shard_replication_factor :-** This parameter determines the number of nodes each shard gets replicated to, and defaults to two. The ideal value for this parameter depends on the size of the cluster and rate of node failure. For example, you may want to increase the replication factor if you run large clusters and observe node failures on a more frequent basis.

.. note::
    The configuration setting citus.shard_replication_factor can only be set on the master node.

Please note that you can load several files in parallel through separate database connections or from different nodes. It is also worth noting that \\copy always creates at least one shard and does not append to existing shards. You can use the method described below to append to previously created shards.

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Incremental loads by appending to existing shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The \\copy command always creates a new shard when it is used and is best suited for bulk loading of data. Using \\copy to load smaller data increments will result in many small shards which might not be ideal. In order to allow smaller, incremental loads into append distributed tables, Citus provides 2 user defined functions. They are master_create_empty_shard() and master_append_table_to_shard().

master_create_empty_shard() can be used to create new empty shards for a table. This function also replicates the empty shard to citus.shard_replication_factor number of nodes like the \\copy command.

master_append_table_to_shard() can be used to append the contents of a PostgreSQL table to an existing shard. This allows the user to control the shard to which the rows will be appended. It also returns the shard fill ratio which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created.

To use the above functionality, you can first insert incoming data into a regular PostgreSQL table. You can then create an empty shard using master_create_empty_shard(). Then, using master_append_table_to_shard(), you can append the contents of the staging table to the specified shard, and then subsequently delete the data from the staging table. Once the shard fill ratio returned by the append function becomes close to 1, you can create a new shard and start appending to the new one.

::

    SELECT * from master_create_empty_shard('github_events');
    master_create_empty_shard
    ---------------------------
                    102089
    (1 row)
    
    SELECT * from master_append_table_to_shard(102089, 'github_events_temp', 'master-101', 5432);
    master_append_table_to_shard 
    ------------------------------               
            0.100548
    (1 row)

To learn more about the two UDFs, their arguments and usage, please visit the :ref:`user_defined_functions` section of the documentation.

Increasing data loading performance
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The methods described above enable you to achieve high bulk load rates which are sufficient for most use cases. If you require even higher data load rates, you can use the functions described above in several ways and write scripts to better control sharding and data loading. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.

Expiring Data
---------------

In append distribution, users typically want to track data only for the last few months / years. In such cases, the shards that are no longer needed still occupy disk space. To address this, Citus provides a user defined function master_apply_delete_command() to delete old shards. The function takes a `DELETE <http://www.postgresql.org/docs/9.5/static/sql-delete.html>`_ command as input and deletes all the shards that match the delete criteria with their metadata.

The function uses shard metadata to decide whether or not a shard needs to be deleted, so it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards are selected for deletion. The UDF then connects to the worker nodes and issues DROP commands for all the shards which need to be deleted. If a drop query for a particular shard replica fails, then that replica is marked as TO DELETE. The shard replicas which are marked as TO DELETE are not considered for future queries and can be cleaned up later.

The example below deletes those shards from the github_events table which have all rows with created_at >= '2015-01-01 00:00:00'. Note that the table is distributed on the created_at column.

::

    SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE created_at >= ''2015-01-01 00:00:00''');
     master_apply_delete_command
    -----------------------------
                               3
    (1 row)

To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.  Please note that this function only deletes complete shards and not individual rows from shards. If your use case requires deletion of individual rows in real-time, see the section below about deleting data.

Deleting Data
---------------

The most flexible way to modify or delete rows throughout a Citus cluster is the master_modify_multiple_shards command. It takes a regular SQL statement as argument and runs it on all workers:

::

  SELECT master_modify_multiple_shards(
    'DELETE FROM github_events WHERE created_at >= ''2015-01-01 00:00:00''');

The function uses a configurable commit protocol to update or delete data safely across multiple shards. Unlike master_apply_delete_command, it works at the row- rather than shard-level to modify or delete all rows that match the condition in the where clause. It deletes rows regardless of whether they comprise an entire shard. To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.

Dropping Tables
---------------

You can use the standard PostgreSQL `DROP TABLE <http://www.postgresql.org/docs/9.5/static/sql-droptable.html>`_
command to remove your append distributed tables. As with regular tables, DROP TABLE removes any
indexes, rules, triggers, and constraints that exist for the target table. In addition, it also
drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;

