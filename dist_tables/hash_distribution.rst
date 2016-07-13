.. _hash_distribution:

Hash Distribution
#################

Hash distributed tables are best suited for use cases which require real-time inserts
and updates. They also allow for faster key-value lookups and efficient joins on the
distribution column. In the next few sections, we describe how
you can create and distribute tables using the hash distribution method, and do real
time inserts and updates to your data in addition to analytics.

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:
    
    ::
        
        export PATH=/usr/lib/postgresql/9.5/:$PATH

We use the github events dataset to illustrate the commands below. You can download that dataset by running:

::
    
    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Creating And Distributing Tables
---------------------------------

To create a hash distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.5/static/sql-createtable.html>`_ statement in the same way as you would do with a regular PostgreSQL table.

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

Next, you can use the master_create_distributed_table() function to mark the table as a hash distributed table and specify its distribution column.

::

    SELECT master_create_distributed_table('github_events', 'repo_id', 'hash');

This function informs Citus that the github_events table should be distributed by hash on the repo_id column.

Then, you can create shards for the distributed table on the worker nodes using the master_create_worker_shards() UDF.

::

    SELECT master_create_worker_shards('github_events', 16, 1);

This UDF takes two arguments in addition to the table name; shard count and the replication factor. This example would create a total of sixteen shards where each shard owns a portion of a hash token space and gets replicated on one worker. The shard replica created on the worker has the same table schema, index, and constraint definitions as the table on the master. Once the replica is created, this function saves all distributed metadata on the master.

Each created shard is assigned a unique shard id and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. You can connect to the worker postgres instances to view or run commands on individual shards.

After creating the worker shard, you are ready to insert data into the hash distributed table and run queries on it. You can also learn more about the UDFs used in this section in the :ref:`user_defined_functions` of our documentation.

Inserting Data
--------------

Single row inserts
$$$$$$$$$$$$$$$$$$

To insert data into hash distributed tables, you can use the standard PostgreSQL `INSERT <http://www.postgresql.org/docs/9.5/static/sql-insert.html>`_ commands. As an example, we pick two rows randomly from the Github Archive dataset.

::

    INSERT INTO github_events VALUES (2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13'); 

    INSERT INTO github_events VALUES (2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24'); 

When inserting rows into hash distributed tables, the distribution column of the row being inserted must be specified. Based on the distribution column, Citus determines the right shard to which the insert should be routed to. Then, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

Bulk loading
$$$$$$$$$$$$

Sometimes, you may want to bulk load several rows together into your hash distributed tables. To bulk load data from a file, you can directly use `PostgreSQL's \\COPY command <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_.

For example:

::
    
    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Updating and Deleting Data
--------------------------

You can also update or delete rows from your tables, using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/9.5/static/sql-update.html>`_ and `DELETE <http://www.postgresql.org/docs/9.5/static/sql-delete.html>`_ commands.

::

    UPDATE github_events SET org = NULL WHERE repo_id = 24509048;
    DELETE FROM github_events WHERE repo_id = 24509048;

Currently, Citus requires that an UPDATE or DELETE involves exactly one shard. This means commands must include a WHERE qualification on the distribution column that restricts the query to a single shard. Such qualifications usually take the form of an equality clause on the table’s distribution column.

Maximizing Write Performance
----------------------------

Both INSERT and UPDATE/DELETE statements can be scaled up to around 50,000 queries per second on large machines. However, to achieve this rate, you will need to use many parallel, long-lived connections and consider how to deal with locking. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.

Dropping Tables
---------------

You can use the standard PostgreSQL DROP TABLE command to remove your hash distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata.

::
    
    DROP TABLE github_events;
