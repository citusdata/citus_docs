.. _distributed_data_modeling:

Distributed modeling refers to choosing how to distribute information across nodes in a multi-machine database cluster and query it efficiently. There are common use cases for a distributed database with well understood design tradeoffs. It will be helpful for you to identify whether your application falls into one of these categories in order to know what features and performance to expect.

Citus uses a column in each table to determine how to allocate its rows among the available shards. In particular, as data is loaded into the table, Citus uses this so-called *distribution column* as a hash key to allocate each incoming row to a shard.

The database administrator, not Citus, picks the distribution column of each table. Thus the main task in distributed modeling is choosing the best division of tables and their distribution columns to fit the queries required by an application.

Determining the Data Model
==========================

As explained in :ref:`when_to_use_citus`, there are two main use cases for Citus. The first is the **multi-tenant architecture** (MT). This is common for the backend of a website that serves other companies, accounts, or organizations. An example of such a site is one which hosts store-fronts and does order processing for other businesses. Sites like these want to continue scaling whether they have hundreds or thousands of tenants -- horizontal scaling with the multi-tenant architecture imposes no hard tenant limit. Additionally, mixing tenant shards across servers in a distributed database results in lower operational costs for this use-case than creating separate servers and database installations for each tenant.

The multi-tenant model as implemented in Citus allows applications to scale with minimal change to their data. It avoids the drastic changes required for alternatives like NoSQL migration and continues to provide the familiar benefits of data normalization, constraints, transactions, joins, and a dedicated query planner. Once data is in the MT architecture it is easy to adjust for a changing application while staying performant. The MT architecture stores all data in the same RDBMS, so changing the data can happen without reconfiguring a constellation of NoSQL services.

There are characteristics of queries and schemas that suggest the multi-tenant architecture. Typical MT queries relate to a single tenant rather than joining information across tenants. This includes the OLTP workload for serving a web clients, and single-tenant OLAP for the site administrator. Having many tables in a database schema is another MT indicator.

The second major Citus use case is **real-time analytics** (RT). The choice of RT vs MT depends on the needs of the application. RT allows the database to ingest a large amount of incoming data and summarize it in real-time. Examples include making dashboards for data from the internet of things, or from web traffic. In this use case applications want massive parallelism, coordinating hundreds of cores for fast results to numerical, statistical, or counting queries.

The real-time architecture usually has few tables, often centering around a big table of device-, site- or user-events. It deals with high volume reads and writes, with relatively simple but computationally intensive lookups. Conversely a schema with many tables or using a rich set of SQL commands is less suited for the real-time architecture.

If your situation resembles either of these cases then the next step is to decide how to shard your data in a Citus cluster. As explained in :ref:`introduction_to_citus`, Citus assigns table rows to shards according to the hashed value of the table's distribution column. The database administrator's choice of distribution columns needs to match the access patterns of typical queries to ensure performance.

Distributing by Tenant ID
=========================

The multi-tenant architecture uses a form of hierarchical database modeling to partition query computations across machines in the distributed cluster. The top of the data hierarchy is known as the *tenant id*, and needs to be stored in a column on each table. Citus inspects queres to see which tenant id they involve and routes the query to a single physical node for processing, specifically the node which holds the data shard associated with the tenant id. Running a query with all relevant data placed on the same node is called *co-location*.

The first step is identifying what constitutes a tenant in your app. Common instances include company, account, organization, or customer. The column name will thus be something like :code:`company_id` or :code:`customer_id:`. Examine each of your queries and ask yourself: would it work if it had additional WHERE clauses to restrict all tables involved to rows with the same tenant id? You can visualize these clauses as executing queries *within* a context, such restricting queries on sales or inventory to be within a certain store.

If you're migrating an existing database to the Citus multi-tenant architecture then some of your tables may lack a column for the application-specific tenant id. You will need to add one and fill it with the correct values. This will denormalize your tables slightly, but it's because the multi-tenant model mixes the characteristics of hierarchical and relational data models. For more details and a concrete example of backfilling the tenant id, see our guide to `Transitioning to Citus`_.

Distributing by Entity ID
=========================

  "All multi-tenant databases are alike; each real-time database is sharded in its own way."

While the multi-tenant architecture introduces a hierarchical structure and uses data co-location to parallelize queries between tenants, real-time architectures depend on specific distribution properties of their data to achieve highly parallel processing.

Real-time queries typically ask for numeric aggregates grouped by date or category. Citus sends these queries to each shard for partial results and assembles the final answer on the coordinator node. Hence queries run fastest when as many nodes contribute as possible, and when no individual node bottlenecks.

Thus it is important to choose a column that distributes data evenly across shards. At the least this column should have a high cardinality. For instance a binary gender field is a poor choice because it assumes at most two values. These values will not be able to take advantage of a cluster with many shards. The row placement will skew into only two shards:

.. image:: ../images/sharding-poorly-distributed.png

Of columns having high cardinality, it is good additionally to choose those that are frequently used in group-by clauses or as join keys. Distributing by join keys co-locates the joined tables and greatly improves join speed. However schemas with many tables and a variety of joins are typically not well suited to the real-time architecture. Real-time schemas usually have a smaller number of tables, and are generally centered around a big table of quantitative events.

Let's examine typical real-time schemas.

Raw Events Table
----------------

In this scenario we ingest high volume sensor measurement events into a single table and distribute it across Citus by the :code:`device_id` of the sensor. Every time the sensor makes a measurement we save that as a single event row with measurement details in a jsonb column for flexibility.

.. code-block:: postgres

  CREATE TABLE events (
    device_id bigint not null,
    event_id uuid NOT NULL DEFAULT gen_random_uuid(),
    event_time timestamptz NOT NULL DEFAULT now(),
    event_type int NOT NULL DEFAULT 0,
    payload jsonb,
    PRIMARY KEY (device_id, event_id)
  );
  CREATE INDEX ON events USING BRIN (event_time);

Any query that restricts to a given device is routed directly to a worker node for processing. We call this a *single-shard* query. Here is one to get the ten most recent events:

.. code-block:: postgres

  SELECT event_time, payload
    FROM events
    WHERE device_id = 298
    ORDER BY event_time DESC
    LIMIT 10;

To take advantage of massive parallelism we can run a *cross-shard* query. For instance, we can find the min, max, and average temperatures per minute across all sensors in the last ten minutes (assuming the json payload includes a :code:`temp` value). We can scale this query to any number of devices by adding worker nodes to the Citus cluster.

.. code-block:: postgres

  SELECT minute,
    min(temperature)::decimal(10,1) AS min_temperature,
    avg(temperature)::decimal(10,1) AS avg_temperature,
    max(temperature)::decimal(10,1) AS max_temperature
  FROM (
    SELECT date_trunc('minute', event_time) AS minute,
           (payload->>'temp')::float AS temperature
    FROM events
    WHERE event_t1me >= now() - interval '10 minutes'
  ) ev
  GROUP BY minute
  ORDER BY minute ASC;

Events and Summaries
--------------------

The previous example calculates statistics at runtime, doing possible recalculation between queries. Another approach is precalculating aggregates. This avoids recalculating raw event data and results in even faster queries. For example, a web analytics dashboard might want a count of views per page per day. The raw events data table looks like this:

.. code-block:: postgres

  CREATE TABLE page_views (
      tenant_id int,
      page_id int,
      host_ip inet,
      view_time timestamp default now()
  );
  CREATE INDEX view_tenant_idx ON page_views (tenant_id);
  CREATE INDEX view_time_idx ON page_views USING BRIN (view_time);

We will precompute the daily view count in this summary table:

.. code-block:: postgres

  CREATE TABLE daily_page_views (
    day date,
    page_id int,
    view_count bigint,
    primary key (day, page_id)
  );

Precomputing aggregates is called *roll-up*. Notice that distributing both tables by :code:`page_id` co-locates their data per-page. Any aggregate functions grouped per page can run in parallel, and this includes aggregates in roll-ups. We can use PostgreSQL `UPSERT <https://www.postgresql.org/docs/current/static/sql-insert.html#SQL-ON-CONFLICT>`_ to create and update rollups, like this (the SQL below takes a parameter for the lower bound timestamp):

.. code-block:: postgres

  INSERT INTO daily_page_views (day, page_id, view_count)
  SELECT view_time::date AS day, page_id, count(*) AS view_count
  FROM page_views
  WHERE view_time >= $1
  GROUP BY view_time::date, page_id
  ON CONFLICT (day, page_id) DO UPDATE SET
    view_count = daily_page_views.view_count + EXCLUDED.view_count;

Updatable Large Table
---------------------

(Device table that has characteristics that get updated. Sharded by device id.)

Behavioral Analytics
--------------------

Whereas the previous examples dealt with a single events table (possibly augmented with precomputed rollups), this example uses two main tables: users and their events. Tracking user behavior is another common Citus use case. In particular consider Wikipedia editors and their edits:

.. code-block:: postgres

  CREATE TABLE wikipedia_editors (
    editor TEXT UNIQUE,
    bot BOOLEAN,

    edit_count INT,
    added_chars INT,
    removed_chars INT,

    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ
  );

  CREATE TABLE wikipedia_changes (
    editor TEXT,
    time TIMESTAMP WITH TIME ZONE,

    wiki TEXT,
    title TEXT,

    comment TEXT,
    minor BOOLEAN,
    type TEXT,

    old_length INT,
    new_length INT
  );

These tables can be populated by the Wikipedia API, and we can distribute them in Citus by the :code:`editor` column. Notice that this is a text column. Citus' hash distribution uses PostgreSQL hashing which supports a number of data types.

A co-located JOIN between editors and changes allows aggregates not only by user, but by properties of a user. For instance we can count the difference between the number of newly created pages by bot vs human. The grouping and counting is performed on worker nodes in parallel and the final results are merged on the coordinator node.

.. code-block:: postgres

  SELECT bot, count(*) AS pages_created
  FROM wikipedia_changes c,
       wikipedia_editors e
  WHERE c.editor = e.editor
    AND type = 'new'
  GROUP BY bot;

Star Schema
-----------

So far we've seen the technique of distributing data where every row goes to exactly one shard. However for small tables there is a trick to achieve a kind of universal colocation. We can choose to place all rows into a single shard but replicate that shard to every worker node. It introduces storage and update costs of course, but this can be more than counterbalanced by the performance gains of read queries.

We call these replicated tables *reference tables.* They usually provide metadata about items in a larger table and are reminiscent of what data warehousing calls dimension tables. For example, suppose we have a large table of phone calls:

.. code-block:: postgres

  CREATE TABLE sales (
    sale_id uuid NOT NULL DEFAULT gen_random_uuid(),
    store_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sold_at timestamptz NOT NULL DEFAULT now(),
    cost money NOT NULL,
    PRIMARY KEY (sale_id)
  );

  CREATE TABLE stores (
    store_id uuid NOT NULL DEFAULT gen_random_uuid(),
    address text NOT NULL,
    region text NOT NULL,
    country text NOT NULL,
    PRIMARY KEY (store_id)
  );

We distribute :code:`sales` by :code:`sale_id` and distribute :ref:`stores` as a reference table across all nodes. At this point we can join these tables efficiently to find, for instance, the top selling regions:

.. code-block:: postgres

  SELECT region, sum(cost) AS total
  FROM sales, stores
  WHERE sales.store_id = stores.store_id
  GROUP BY region;

Modeling Concepts
=================


