.. _hash_inserting_data:

Inserting Data
##############

Single row inserts
--------------------

To insert data into hash distributed tables, you can use the standard PostgreSQL `INSERT <http://www.postgresql.org/docs/9.4/static/sql-insert.html>`_ commands. As an example, we pick two rows randomly from the Github Archive dataset.


::

    INSERT INTO github_events VALUES (2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13'); 

    INSERT INTO github_events VALUES (2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24'); 

When inserting rows into hash distributed tables, the distribution column of the row being inserted must be specified. To execute the insert query, first the value of the distribution column in the incoming row is hashed. Then, the database determines the right shard in which the row should go by looking at the corresponding hash ranges of the shards. On the basis of this information, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

Bulk inserts
------------------------

Sometimes, users may want to bulk load several rows together into their hash distributed tables. To facilitate this, a script named copy_to_distributed_table is provided for loading many rows of data from a file, similar to the functionality provided by `PostgreSQL's COPY command <http://www.postgresql.org/docs/current/static/sql-copy.html>`_. It is automatically installed into the bin directory for your CitusDB installation.

Before invoking the script, we set the PATH environment variable to include the CitusDB bin directory.

::

    export PATH=/opt/citusdb/4.0/bin/:$PATH

Next, you should set the environment variables which will be used as connection parameters while connecting to your postgres server. For example, to set the default database to postgres, you can run the command shown below.

::

    export PGDATABASE=postgres


As an example usage for the script, the invocation below would copy rows into the github_events table from a CSV file.

::
    
    /opt/citusdb/4.0/bin/copy_to_distributed_table -C github_events-2015-01-01.csv github_events

To learn more about the different options supported by the script, you can call the script with -h for usage information.

::

    /opt/citusdb/4.0/bin/copy_to_distributed_table -h

Note that hash distributed tables are optimised for real-time ingestion, where users typically have to do single row inserts into distributed tables. Bulk loading, though supported, is generally slower than tables using the append distribution method. For use cases involving bulk loading of data, please consider using :ref:`append_distribution`.
