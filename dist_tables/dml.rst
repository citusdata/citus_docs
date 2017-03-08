.. _dml:

Ingesting, Modifying Data (DML)
###############################

The following code snippets use the Github events example, see :ref:`ddl`.

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

First download our example github_events dataset by running:

.. code-block:: bash

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
    gzip -d github_events-2015-01-01-*.gz


Then, you can copy the data using psql:

.. code-block:: postgresql

    \COPY github_events FROM 'github_events-2015-01-01-0.csv' WITH (format CSV)

.. note::

    There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g.  exclude the most recent data from queries, or use some lock).

    If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made.

Distributed Aggregations
$$$$$$$$$$$$$$$$$$$$$$$$

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

It's worth noting that for :code:`INSERT INTO ... SELECT` to work on distributed tables, Citus requires the source and destination table to be co-located. In summary:

- The tables queried and inserted are distributed by analogous columns
- The select query includes the distribution column
- The insert statement includes the distribution column

The rollup query above aggregates data from the previous day and inserts it into :code:`daily_page_views`. Running the query once each day means that no rollup tables rows need to be updated, because the new day's data does not affect previous rows.

The situation changes when dealing with late arriving data, or running the rollup query more than once per day. If any new rows match days already in the rollup table, the matching counts should increase. PostgreSQL can handle this situation with "ON CONFLICT," which is its technique for doing `upserts <https://www.postgresql.org/docs/9.5/static/sql-insert.html#SQL-ON-CONFLICT>`_. Here is an example.

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

Single-Shard Updates and Deletion
---------------------------------

You can update or delete rows from your tables, using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/9.6/static/sql-update.html>`_ and `DELETE <http://www.postgresql.org/docs/9.6/static/sql-delete.html>`_ commands.

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
