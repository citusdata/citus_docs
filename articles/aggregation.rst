Real-time Event Aggregation at Scale Using Postgres with Citus
==============================================================

(Copy of `original publication <https://www.citusdata.com/blog/2016/11/29/event-aggregation-at-scale-with-postgresql/>`__)

.. NOTE::

   This article mentions the Citus Cloud service.  We are no longer onboarding
   new users to Citus Cloud on AWS. If you’re new to Citus, the good news is,
   Citus is still available to you: as open source, and in the cloud on
   Microsoft Azure, as a fully-integrated deployment option in Azure Database
   for PostgreSQL.

   See :ref:`cloud_topic`.

Citus is commonly used to scale out event data pipelines on top of
PostgreSQL. Its ability to transparently shard data and parallelise
queries over many machines makes it possible to have real-time
responsiveness even with terabytes of data. Users with very high data
volumes often store pre-aggregated data to avoid the cost of processing
raw data at run-time. For large datasets, querying pre-computed
aggregation tables can be orders of magnitude faster than querying the
facts table on demand.

To create aggregations for distributed tables, the latest version of
Citus supports the INSERT .. SELECT syntax for tables that use the same
distribution column. Citus automatically 'co-locates' the shards of
distributed tables such that the same distribution column value is
always placed on the same worker node, which allows us to transfer data
between tables as long as the distribution column value is preserved. A
common way of taking advantage of co-location is to follow the
:ref:`multi-tenant data model <distributing_by_tenant_id>`
and shard all tables by tenant\_id or customer\_id. Even without that
model, as long as your tables share the same distribution column, you
can leverage the INSERT .. SELECT syntax.

INSERT .. SELECT queries that can be pushed down to the workers are
supported, which excludes some SQL functionality such as limits, and
unions. Since the result will be inserted into a co-located shard in the
destination table, we need to make sure that the distribution column
(e.g. tenant\_id) is preserved in the aggregation and is included in
joins. INSERT .. SELECT commands on distributed tables will usually look
like:

.. code-block:: postgres

    INSERT INTO aggregation_table (tenant_id, ...)
    SELECT tenant_id, ... FROM facts_table ...

Now let's walk through the steps of creating aggregations for a typical
example of high-volume data: page views. We set up a `Citus Cloud
<https://www.citusdata.com/product/cloud/>`__ formation consisting
of 4 workers with 4 cores each, and create a distributed `facts
<http://databases.about.com/od/datamining/a/Facts-Vs-Dimensions.htm>`__
table with several indexes:

.. code-block:: postgres

    CREATE TABLE page_views (
        tenant_id int,
        page_id int,
        host_ip inet,
        view_time timestamp default now()
    );
    CREATE INDEX view_tenant_idx ON page_views (tenant_id);
    CREATE INDEX view_time_idx ON page_views USING BRIN (view_time);

    SELECT create_distributed_table('page_views', 'tenant_id');

Next, we generate 100 million rows of fake data (takes a few minutes)
and load it into the database:

.. code-block:: psql

    \COPY (SELECT s % 307, (random()*5000)::int, '203.0.113.' || (s % 251), now() + random() * interval '60 seconds' FROM generate_series(1,100000000) s) TO '/tmp/views.csv' WITH CSV

    \COPY page_views FROM '/tmp/views.csv' WITH CSV

We can now perform aggregations at run-time by performing a SQL query
against the facts table:

.. code-block:: postgres

    -- Most views in the past week
    SELECT page_id, count(*) AS view_count
    FROM page_views
    WHERE tenant_id = 5 AND view_time >= date '2016-11-23'
    GROUP BY tenant_id, page_id
    ORDER BY view_count DESC LIMIT 3;
     page_id | view_count 
    ---------+------------
        2375 |         99
        4538 |         95
        1417 |         93
    (3 rows)

    Time: 269.125 ms

However, we can do *much* better by creating a pre-computed aggregation,
which we also distribute by tenant\_id. Citus automatically co-locates
the table with the page\_views table:

.. code-block:: postgres

    CREATE TABLE daily_page_views (
        tenant_id int,
        day date,
        page_id int,
        view_count bigint,
        primary key (tenant_id, day, page_id)
    );

    SELECT create_distributed_table('daily_page_views', 'tenant_id');

We can now populate the aggregation using a simple INSERT..SELECT
command, which is parallelised across the cores in our workers,
processing around *10 million events per second* and generating 1.7
million aggregates:

.. code-block:: postgres

    INSERT INTO daily_page_views (tenant_id, day, page_id, view_count)
      SELECT tenant_id, view_time::date AS day, page_id, count(*) AS view_count
      FROM page_views
      GROUP BY tenant_id, view_time::date, page_id;

    INSERT 0 1690649

    Time: 10649.870 ms 

After creating the aggregation, we can get the results from the
aggregation table in a fraction of the query time:

.. code-block:: postgres

    -- Most views in the past week
    SELECT page_id, view_count
    FROM daily_page_views
    WHERE tenant_id = 5 AND day >= date '2016-11-23'
    ORDER BY view_count DESC LIMIT 3;
     page_id | view_count 
    ---------+------------
        2375 |         99
        4538 |         95
        1417 |         93
    (3 rows)

    Time: 4.528 ms

We typically want to keep aggregations up-to-date, even as the current
day progresses. We can achieve this by expanding our original command to
only consider new rows and updating existing rows to consider the new
data using
`ON CONFLICT <https://www.postgresql.org/docs/current/static/sql-insert.html#SQL-ON-CONFLICT>`__.
If we insert data for a primary key (tenant\_id, day, page\_id) that
already exists in the aggregation table, then the count will be added
instead.

.. code-block:: postgres

    INSERT INTO page_views VALUES (5, 10, '203.0.113.1');


    INSERT INTO daily_page_views (tenant_id, day, page_id, view_count)
      SELECT tenant_id, view_time::date AS day, page_id, count(*) AS view_count
      FROM page_views
      WHERE view_time >= '2016-11-23 23:00:00' AND view_time < '2016-11-24 00:00:00'
      GROUP BY tenant_id, view_time::date, page_id
      ON CONFLICT (tenant_id, day, page_id) DO UPDATE SET
      view_count = daily_page_views.view_count + EXCLUDED.view_count;

    INSERT 0 1

    Time: 2787.081 ms

To regularly update the aggregation, we need to keep track of which rows
in the facts table have already been processed as to avoid counting them
more than once. A basic approach is to aggregate up to the current time,
store the timestamp in a table, and continue from that timestamp on the
next run. We do need to be careful that there may be in-flight requests
with a lower timestamp, which is especially true when using bulk
ingestion through COPY. We therefore roll up to a timestamp that lies
slightly in the past, with the assumption that all requests that started
before then have finished by now. We can easily codify this logic into a
PL/pgSQL function:

.. code-block:: postgres

    CREATE TABLE aggregations (name regclass primary key, last_update timestamp);
    INSERT INTO aggregations VALUES ('daily_page_views', now());


    CREATE OR REPLACE FUNCTION compute_daily_view_counts()
    RETURNS void LANGUAGE plpgsql AS $function$
    DECLARE
      start_time timestamp;
      end_time timestamp := now() - interval '1 minute'; -- exclude in-flight requests
    BEGIN
      SELECT last_update INTO start_time FROM aggregations WHERE name = 'daily_page_views'::regclass;
      UPDATE aggregations SET last_update = end_time WHERE name = 'daily_page_views'::regclass;

      EXECUTE $$
        INSERT INTO daily_page_views (tenant_id, day, page_id, view_count)
          SELECT tenant_id, view_time::date AS day, page_id, count(*) AS view_count
          FROM page_views
          WHERE view_time >= $1 AND view_time < $2
          GROUP BY tenant_id, view_time::date, page_id
          ON CONFLICT (tenant_id, day, page_id) DO UPDATE SET
          view_count = daily_page_views.view_count + EXCLUDED.view_count$$
      USING start_time, end_time;
    END;
    $function$;

After creating the function, we can periodically call
``SELECT compute_daily_view_counts()`` to continuously update the
aggregation with 1-2 minutes delay. More advanced approaches can bring
down this delay to a few seconds.

In this example, we used a single, database-generated time column, but it's
generally better to distinguish between the time at which the event happened at
the source and the database-generated ingestion time used to keep track of
whether an event was already processed.

You might be wondering why we used a page\_id in the examples instead of
something more meaningful like a URL. Are we trying to dodge the
overhead of storing URLs for every page view to make our numbers look
better? We certainly are! With Citus you can often avoid the cost of
denormalization that you would pay in distributed databases that don't
support joins. You can simply put the static details of a page inside
another table and perform a join:

.. code-block:: postgres

    CREATE TABLE pages (
        tenant_id int,
        page_id int,
        url text,
        language varchar(2),
        primary key (tenant_id, page_id)
    );

    SELECT create_distributed_table('pages', 'tenant_id');

    ... insert pages ...

    -- Most views in the past week
    SELECT url, view_count
    FROM daily_page_views JOIN pages USING (tenant_id, page_id)
    WHERE tenant_id = 5 AND day >= date '2016-11-23'
    ORDER BY view_count DESC LIMIT 3;
       url    | view_count 
    ----------+------------
     /home    |         99
     /contact |         95
     /product |         93
    (3 rows)

    Time: 7.042 ms

You can also perform joins in the INSERT..SELECT command, allowing you
to create more detailed aggregations, e.g. by language.

Distributed aggregation adds another tool to Citus' broad toolchest in dealing
with big data problems. With parallel INSERT .. SELECT, parallel indexing,
parallel querying, and many other features, Citus can not only horizontally
scale your multi-tenant database, but can also unify many different parts of
your data pipeline into one platform.
