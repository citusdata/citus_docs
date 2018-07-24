.. _dml:

Ingesting, Modifying Data (DML)
===============================

Inserting Data
--------------

To insert data into distributed tables, you can use the standard PostgreSQL `INSERT <http://www.postgresql.org/docs/current/static/sql-insert.html>`_ commands. As an example, we pick two rows randomly from the Github Archive dataset.

.. code-block:: sql

    /*
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
    */

    INSERT INTO github_events VALUES (2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13');

    INSERT INTO github_events VALUES (2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24');

When inserting rows into distributed tables, the distribution column of the row being inserted must be specified. Based on the distribution column, Citus determines the right shard to which the insert should be routed. Then, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

Sometimes it's convenient to put multiple insert statements together into a single insert of multiple rows. It can also be more efficient than making repeated database queries. For instance, the example from the previous section can be loaded all at once like this:

.. code-block:: sql

    INSERT INTO github_events VALUES
      (
        2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13'
      ), (
        2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24'
      );

"From Select" Clause (Distributed Rollups)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus also supports ``INSERT … SELECT`` statements -- which insert rows based on the results of a select query. This is a convenient way to fill tables and also allows "upserts" with the ``ON CONFLICT`` clause.

In Citus there are two ways that inserting from a select statement can happen. The first is if the source tables and destination table are :ref:`colocated <colocation>`, and the select/insert statements both include the distribution column. In this case Citus can push the ``INSERT … SELECT`` statement down for parallel execution on all nodes. Pushing the statement down supports the ``ON CONFLICT`` clause, the easiest way to do :ref:`distributed rollups <rollups>`.

The second way of executing an ``INSERT … SELECT`` statement is selecting the results from worker nodes, pulling the data up to the coordinator node, and then issuing an INSERT statement from the coordinator with the data. Citus is forced to use this approach when the source and destination tables are not colocated. This method does not support ``ON CONFLICT``.

When in doubt about which method Citus is using, use the EXPLAIN command, as described in :ref:`postgresql_tuning`.

COPY Command (Bulk load)
~~~~~~~~~~~~~~~~~~~~~~~~

To bulk load data from a file, you can directly use `PostgreSQL's \\COPY command <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_.

First download our example github_events dataset by running:

.. code-block:: bash

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Then, you can copy the data using psql:

.. code-block:: psql

    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Updates and Deletion
--------------------

You can update or delete rows from your distributed tables using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/current/static/sql-update.html>`_ and `DELETE <http://www.postgresql.org/docs/current/static/sql-delete.html>`_ commands.

.. code-block:: sql

    DELETE FROM github_events
    WHERE repo_id IN (24509048, 24509049);

    UPDATE github_events
    SET event_public = TRUE
    WHERE (org->>'id')::int = 5430905;

When updates/deletes affect multiple shards as in the above example, Citus defaults to using a one-phase commit protocol. For greater safety you can enable two-phase commits by setting

.. code-block:: postgresql

  SET citus.multi_shard_commit_protocol = '2pc';

If an update or delete affects only a single shard then it runs within a single worker node. In this case enabling 2PC is unnecessary. This often happens when updates or deletes filter by a table's distribution column:

.. code-block:: postgresql

  -- since github_events is distributed by repo_id,
  -- this will execute in a single worker node

  DELETE FROM github_events
  WHERE repo_id = 206084;

Furthermore, when dealing with a single shard, Citus supports ``SELECT … FOR UPDATE``. This is a technique sometimes used by object-relational mappers (ORMs) to safely:

1. load rows
2. make a calculation in application code
3. update the rows based on calculation

Selecting the rows for update puts a write lock on them to prevent other processes from causing a "lost update" anomaly.

.. code-block:: sql

  BEGIN;

    -- select events for a repo, but
    -- lock them for writing
    SELECT *
    FROM github_events
    WHERE repo_id = 206084
    FOR UPDATE;

    -- calculate a desired value event_public using
    -- application logic that uses those rows...

    -- now make the update
    UPDATE github_events
    SET event_public = :our_new_value
    WHERE repo_id = 206084;

  COMMIT;

This feature is supported for hash distributed and reference tables only, and only those that have a :ref:`replication_factor <replication_factor>` of 1.

Maximizing Write Performance
----------------------------

Both INSERT and UPDATE/DELETE statements can be scaled up to around 50,000 queries per second on large machines. However, to achieve this rate, you will need to use many parallel, long-lived connections and consider how to deal with locking. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.
