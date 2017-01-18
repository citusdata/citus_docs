.. _dml:

Ingesting, Modifying Data (DML)
###############################

The following code snippets use the distributed tables example dataset, see :ref:`ddl`.

Inserting Data
--------------

Single row inserts
$$$$$$$$$$$$$$$$$$

To insert data into distributed tables, you can use the standard PostgreSQL `INSERT <http://www.postgresql.org/docs/9.6/static/sql-insert.html>`_ commands. As an example, we pick two rows randomly from the Github Archive dataset.

::

    INSERT INTO github_events VALUES (2489373118,'PublicEvent','t',24509048,'{}','{"id": 24509048, "url": "https://api.github.com/repos/SabinaS/csee6868", "name": "SabinaS/csee6868"}','{"id": 2955009, "url": "https://api.github.com/users/SabinaS", "login": "SabinaS", "avatar_url": "https://avatars.githubusercontent.com/u/2955009?", "gravatar_id": ""}',NULL,'2015-01-01 00:09:13'); 

    INSERT INTO github_events VALUES (2489368389,'WatchEvent','t',28229924,'{"action": "started"}','{"id": 28229924, "url": "https://api.github.com/repos/inf0rmer/blanket", "name": "inf0rmer/blanket"}','{"id": 1405427, "url": "https://api.github.com/users/tategakibunko", "login": "tategakibunko", "avatar_url": "https://avatars.githubusercontent.com/u/1405427?", "gravatar_id": ""}',NULL,'2015-01-01 00:00:24'); 

When inserting rows into distributed tables, the distribution column of the row being inserted must be specified. Based on the distribution column, Citus determines the right shard to which the insert should be routed to. Then, the query is forwarded to the right shard, and the remote insert command is executed on all the replicas of that shard.

Bulk loading
$$$$$$$$$$$$

Sometimes, you may want to bulk load several rows together into your distributed tables. To bulk load data from a file, you can directly use `PostgreSQL's \\COPY command <http://www.postgresql.org/docs/current/static/app-psql.html#APP-PSQL-META-COMMANDS-COPY>`_.

For example:

::

    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Inserting from a Query
$$$$$$$$$$$$$$$$$$$$$$

Applications like event data pipelines and real-time dashboards require fast queries across predefined aggregations of incoming data. One way to make these queries fast is by calculating and saving aggregates ahead of time. This is called "rolling up" the data and it avoids the cost of processing raw data at run-time. As an extra benefit, rolling up timeseries data into hourly or daily statistics can also save space. Old data may be deleted when its full details are no longer needed and aggregates suffice.

For example, here is a table for tracking page views by url and a query to aggregate views per day.

.. code-block:: postgresql

  CREATE TABLE page_views (
    site_id int,
    url text,
    host_ip inet,
    view_time timestamp default now(),

    PRIMARY KEY (site_id, url)
  );

  SELECT view_time::date AS day, site_id, url,
         count(*) AS view_count
  FROM page_views
  GROUP BY view_time::date, site_id, url;

One disadvantage of repeatedly executing the aggregate query is that it always has to recompute on the whole dataset. It's faster to save the information to a roll up :code:`daily_page_views` table and query that. We create the table and use :code:`INSERT INTO ... SELECT` to populate the table directly from the results of a query:

.. code-block:: postgresql

  CREATE TABLE daily_page_views (
    site_id int,
    day date,
    url text,
    view_count bigint,
    PRIMARY KEY (site_id, day, url)
  );

  INSERT INTO daily_page_views (day, site_id, url, view_count)
    -- this is our original select query
    SELECT view_time::date AS day, site_id, url,
           count(*) AS view_count
    FROM page_views
    GROUP BY view_time::date, site_id, url;

  -- now the results are available right out of the table
  SELECT day, site_id, url, view_count
  FROM daily_page_views;


However as the numbers of tracked web sites and their pages grow, the aggregate query for populating (or as we'll see later, updating) the rollup table slows down. However we can combine rollup tables and distributed computing to scale the application. Since we GROUP BY each site separately we can parallelize the computation across nodes in a distributed database. Each node in a Citus cluster can hold the data for different web sites and the nodes can each compute rollups locally and write a corresponding part of :code:`daily_page_views`. We distribute both :code:`page_views` and :code:`daily_page_views` so that their rows will stay on the same machine when their :code:`site_id` values match.

.. code-block:: postgresql

  -- First distribute the tables. Notice how we're using the
  -- same distribution column to keep page views and their daily
  -- summaries on the same machine

  SELECT create_distributed_table('page_views', 'site_id');
  SELECT create_distributed_table('daily_page_views', 'site_id');

Keeping the tables' information together on each node, i.e. `co-locating <colocation_groups>`_ them, minimizes network traffic between nodes and allows highly parallel execution. In fact for INSERT INTO SELECT to work in Citus, colocation isn't just a good idea, it's the law. Citus requires the source and destination table to be colocated and throws an error if they are not. Citus implements INSERT INTO SELECT by pushing down the select query to each shard. The distributed query execution happens automatically, just use the ordinary SQL command.

.. code-block:: postgresql

  -- Then run the ordinary INSERT INTO SELECT as before

  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url,
           count(*) AS view_count
    FROM page_views
    GROUP BY view_time::date, site_id, url;


In summary, INSERT INTO SELECT on Citus requires that:

- The tables queried and inserted are distributed by analogous columns
- The select query includes the distribution column
- The insert statement includes the distribution column

Rollups keep statistics queries fast but do require upkeep. New items must be periodically added or existing entries updated. In order that this periodic update be fast we need to do it *incrementally*, meaning without having to re-scan the entire underlying dataset (as, for instance, a materialized view would require). PostgreSQL's upsert feature is what we need.

Suppose we have already rolled up visits happening before a certain timestamp (we'll call it :code:`$1`) and want to update the rollups to include more recent views. To do this we add a WHERE clause to select visits after the timestamp, and specify "ON CONFLICT" to adjust any daily view aggregates the new data affects. The latter is PostgreSQL's technique for doing `upserts <https://www.postgresql.org/docs/9.5/static/sql-insert.html#SQL-ON-CONFLICT>`_.

.. code-block:: postgresql

  INSERT INTO daily_page_views (day, site_id, url, view_count)
    SELECT view_time::date AS day, site_id, url,
           count(*) AS view_count
    FROM page_views
    WHERE view_time >= $1
    GROUP BY view_time::date, site_id, url;
    ON CONFLICT (day, url, site_id) DO UPDATE SET
      view_count = daily_page_views.view_count + EXCLUDED.view_count;

Querying the distributed rollup table is easy:

.. code-block:: postgresql

  SELECT day, site_id, url, view_count
  FROM daily_page_views;

Single-Shard Updates and Deletion
---------------------------------

You can also update or delete rows from your tables, using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/9.6/static/sql-update.html>`_ and `DELETE <http://www.postgresql.org/docs/9.6/static/sql-delete.html>`_ commands.

::

    UPDATE github_events SET org = NULL WHERE repo_id = 24509048;
    DELETE FROM github_events WHERE repo_id = 24509048;


Currently, Citus requires that standard UPDATE or DELETE statements involve exactly one shard. This means commands must include a WHERE qualification on the distribution column that restricts the query to a single shard. Such qualifications usually take the form of an equality clause on the table’s distribution column. To update or delete across shards see the section below.

Cross-Shard Updates and Deletion
--------------------------------

The most flexible way to modify or delete rows throughout a Citus cluster is the master_modify_multiple_shards command. It takes a regular SQL statement as argument and runs it on all workers:

::

  SELECT master_modify_multiple_shards(
    'DELETE FROM github_events WHERE repo_id IN (24509048, 24509049)');

This uses a two-phase commit to remove or update data safely everywhere. Unlike the standard UPDATE statement, Citus allows it to operate on more than one shard. To learn more about the function, its arguments and its usage, please visit the :ref:`user_defined_functions` section of our documentation.

Maximizing Write Performance
----------------------------

Both INSERT and UPDATE/DELETE statements can be scaled up to around 50,000 queries per second on large machines. However, to achieve this rate, you will need to use many parallel, long-lived connections and consider how to deal with locking. For more information, you can consult the :ref:`scaling_data_ingestion` section of our documentation.
