.. _ddl:

Creating Distributed Tables (DDL)
#################################

.. _dist_tables_dataset:

Example Dataset
---------------

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:

    ::

        export PATH=/usr/lib/postgresql/9.5/:$PATH

We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Creating And Distributing Tables
--------------------------------

To create a distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.5/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

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

Next, you can use the master_create_distributed_table() function to specify the table distribution column.

::

    SELECT master_create_distributed_table('github_events', 'repo_id', 'hash');

This function informs Citus that the github_events table should be distributed on the repo_id column (by hashing the column value).

Then, you can create shards for the distributed table on the worker nodes using the master_create_worker_shards() UDF.

::

    SELECT master_create_worker_shards('github_events', 16, 1);

This UDF takes two arguments in addition to the table name; shard count and the replication factor. This example would create a total of sixteen shards where each shard owns a portion of a hash token space and gets replicated on one worker. The shard replica created on the worker has the same table schema, index, and constraint definitions as the table on the master. Once the replica is created, this function saves all distributed metadata on the master.

Each created shard is assigned a unique shard id and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. You can connect to the worker postgres instances to view or run commands on individual shards.

After creating the worker shard, you are ready to insert data into the distributed table and run queries on it. You can also learn more about the UDFs used in this section in the :ref:`user_defined_functions` of our documentation.

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

::

    DROP TABLE github_events;
