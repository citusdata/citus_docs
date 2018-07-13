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

The situation changes when dealing with late arriving data, or running the rollup query more than once per day. If any new rows match days already in the rollup table, the matching counts should increase. PostgreSQL can handle this situation with "ON CONFLICT," which is its technique for doing `upserts <https://www.postgresql.org/docs/10/static/sql-insert.html#SQL-ON-CONFLICT>`_. Here is an example.

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
