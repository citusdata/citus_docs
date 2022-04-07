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

When inserting rows into distributed tables, the distribution column of the row being inserted must be specified. Based on the distribution column, Citus determines the right shard to which the insert should be routed to. Then, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

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

Citus also supports ``INSERT … SELECT`` statements -- which insert rows based on the results of a select query. This is a convenient way to fill tables and also allows "upserts" with the ``ON CONFLICT`` clause, the easiest way to do :ref:`distributed rollups <rollups>`.

In Citus there are three ways that inserting from a select statement can happen. The first is if the source tables and destination table are :ref:`colocated <colocation>`, and the select/insert statements both include the distribution column. In this case Citus can push the ``INSERT … SELECT`` statement down for parallel execution on all nodes.

The second way of executing an ``INSERT … SELECT`` statement is by repartitioning the results of the result set into chunks, and sending those chunks among workers to matching destination table shards. Each worker node can insert the values into local destination shards.

The repartitioning optimization can happen when the SELECT query doesn't require a merge step on the coordinator. It doesn't work with the following SQL features, which require a merge step:

* ORDER BY
* LIMIT
* OFFSET
* GROUP BY when distribution column is not part of the group key
* Window functions when partitioning by a non-distribution column in the source table(s)
* Joins between non-colocated tables (i.e. repartition joins)

When the source and destination tables are not colocated, and the repartition optimization cannot be applied, then Citus uses the third way of executing ``INSERT … SELECT``. It selects the results from worker nodes, and pulls the data up to the coordinator node. The coordinator redirects rows back down to the appropriate shard. Because all the data must pass through a single node, this method is not as efficient.

When in doubt about which method Citus is using, use the EXPLAIN command, as described in :ref:`postgresql_tuning`. When the target table has a very large shard count, it may be wise to disable repartitioning, see :ref:`enable_repartitioned_insert_select`.

COPY Command (Bulk load)
~~~~~~~~~~~~~~~~~~~~~~~~

To bulk load data from a file, you can directly use `PostgreSQL's \\COPY command <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_.

First download our example github_events dataset by running:

.. code-block:: bash

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz

Then, you can copy the data using psql (note that this data requires the database to have UTF8 encoding):

.. code-block:: psql

    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

.. _rollups:

Caching Aggregations with Rollups
=================================

Applications like event data pipelines and real-time dashboards require sub-second queries on large volumes of data. One way to make these queries fast is by calculating and saving aggregates ahead of time. This is called "rolling up" the data and it avoids the cost of processing raw data at run-time. As an extra benefit, rolling up timeseries data into hourly or daily statistics can also save space. Old data may be deleted when its full details are no longer needed and aggregates suffice.

For example, here is a distributed table for tracking page views by url:

.. code-block:: postgresql

  CREATE TABLE page_views (
    site_id int,
    url text,
    host_ip inet,
    view_time timestamp default now(),

    PRIMARY KEY (site_id, url)
  );

  SELECT create_distributed_table('page_views', 'site_id');

Once the table is populated with data, we can run an aggregate query to count page views per URL per day, restricting to a given site and year.

.. code-block:: postgresql

  -- how many views per url per day on site 5?
  SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE site_id = 5 AND
      view_time >= date '2016-01-01' AND view_time < date '2017-01-01'
    GROUP BY view_time::date, site_id, url;

The setup described above works, but has two drawbacks. First, when you repeatedly execute the aggregate query, it must go over each related row and recompute the results for the entire data set. If you're using this query to render a dashboard, it's faster to save the aggregated results in a daily page views table and query that table. Second, storage costs will grow proportionally with data volumes and the length of queryable history. In practice, you may want to keep raw events for a short time period and look at historical graphs over a longer time window.

To receive those benefits, we can create a :code:`daily_page_views` table to store the daily statistics.

.. code-block:: postgresql

  CREATE TABLE daily_page_views (
    site_id int,
    day date,
    url text,
    view_count bigint,
    PRIMARY KEY (site_id, day, url)
  );

  SELECT create_distributed_table('daily_page_views', 'site_id');

In this example, we distributed both :code:`page_views` and :code:`daily_page_views` on the :code:`site_id` column. This ensures that data corresponding to a particular site will be :ref:`co-located <colocation>` on the same node. Keeping the two tables' rows together on each node minimizes network traffic between nodes and enables highly parallel execution.

Once we create this new distributed table, we can then run :code:`INSERT INTO ... SELECT` to roll up raw page views into the aggregated table. In the following, we aggregate page views each day. Citus users often wait for a certain time period after the end of day to run a query like this, to accommodate late arriving data.

.. code-block:: postgresql

  -- roll up yesterday's data
  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE view_time >= date '2017-01-01' AND view_time < date '2017-01-02'
    GROUP BY view_time::date, site_id, url;

  -- now the results are available right out of the table
  SELECT day, site_id, url, view_count
    FROM daily_page_views
    WHERE site_id = 5 AND
      day >= date '2016-01-01' AND day < date '2017-01-01';

The rollup query above aggregates data from the previous day and inserts it into :code:`daily_page_views`. Running the query once each day means that no rollup tables rows need to be updated, because the new day's data does not affect previous rows.

The situation changes when dealing with late arriving data, or running the rollup query more than once per day. If any new rows match days already in the rollup table, the matching counts should increase. PostgreSQL can handle this situation with "ON CONFLICT," which is its technique for doing `upserts <https://www.postgresql.org/docs/current/static/sql-insert.html#SQL-ON-CONFLICT>`_. Here is an example.

.. code-block:: postgresql

  -- roll up from a given date onward,
  -- updating daily page views when necessary
  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url, count(*) AS view_count
    FROM page_views
    WHERE view_time >= date '2017-01-01'
    GROUP BY view_time::date, site_id, url
    ON CONFLICT (day, url, site_id) DO UPDATE SET
      view_count = daily_page_views.view_count + EXCLUDED.view_count;

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

This feature is supported for hash distributed and reference tables only.

Maximizing Write Performance
----------------------------

Both INSERT and UPDATE/DELETE statements can be scaled up to around 50,000 queries per second on large machines. However, to achieve this rate, you will need to use many parallel, long-lived connections and consider how to deal with locking. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.
