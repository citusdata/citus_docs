.. _hash_dropping_tables:

Dropping Tables
###############

CitusDB users can use the standard PostgreSQL DROP TABLE command to remove their hash distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table.

Please note that this only removes the table's definition but not the metadata or the table's shards from the worker nodes. If disk space becomes an issue, users can connect to the worker nodes and manually drop the old shards for their hash partitioned tables.

::
    
    postgres=# DROP TABLE github_events;
    DROP TABLE
