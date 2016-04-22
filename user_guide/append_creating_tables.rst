.. _append_creating_tables:

Creating Tables
###############

To create an append distributed table, users can connect to the master node and create a table by issuing a CREATE TABLE command like below.

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
    ) DISTRIBUTE BY APPEND (created_at);

This command creates a new distributed table, and has almost the same syntax as PostgreSQL's `CREATE TABLE <http://www.postgresql.org/docs/9.4/static/sql-createtable.html>`_ command. The only difference is that the command has a distribute by append clause at the end, which tells the database about the distribution column. Note that this method doesn't in fact enforce a particular distribution; it merely tells the database to keep minimum and maximum values for the created_at column in each shard which are later used by the database.
