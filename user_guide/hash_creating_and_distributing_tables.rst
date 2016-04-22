.. _hash_creating_and_distributing_tables:

Creating And Distributing Tables
################################


To create a hash distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.4/static/sql-createtable.html>`_ statement in the same way as you would do with a regular postgresql table.

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

Next, you need to specify the distribution column for the table. This can be done by using the master_create_distributed_table() UDF. 

::

    SELECT master_create_distributed_table('github_events', 'repo_id');


This function informs the database that the github_events table should be distributed by hash on the repo_id column.

Then, you can create shards for the distributed table on the worker nodes using the master_create_worker_shards() UDF.

::

    SELECT master_create_worker_shards('github_events', 16, 2);

This UDF takes two arguments in addition to the table name; shard count and the replication factor. This example would create a total of 16 shards where each shard owns a portion of a hash token space and gets replicated on 2 worker nodes. The shard replicas created on the worker nodes have the same table schema, index, and constraint definitions as the table on the master node. Once all replicas are created, this function saves all distributed metadata on the master node.

Each created shard is assigned a unique shard id and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. You can connect to the worker postgres instances to view or run commands on individual shards.

After creating the worker shards, you are ready to insert your data into the hash distributed table and run analytics queries on it. You can also learn more about the UDFs used in this section in the :ref:`user_defined_functions` of our documentation.
