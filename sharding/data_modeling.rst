.. _distributed_data_modeling:

Determining Application Type
============================

Running efficient queries on a Citus cluster requires that data be properly distributed across machines. This varies by the type of application and its query patterns.

There are broadly two kinds of applications that work very well on Citus. The first step in data modeling is to identify which of them more closely resembles your application:

**Multi-Tenant Application**

  B2B applications that serve other companies, accounts, or organizations.

  * **Examples**: Websites which host store-fronts for other businesses, such as a digital marketing solution, or a sales automation tool.
  * **Characteristics**: Queries relating to a single tenant rather than joining information across tenants. This includes OLTP workloads for serving web clients, and OLAP workloads that serve per-tenant analytical queries. Having dozens or hundreds of tables in your database schema is also an indicator for the multi-tenant data model.

**Real-Time Analytics**

  Applications needing massive parallelism, coordinating hundreds of cores for fast results to numerical, statistical, or counting queries.

  * **Examples**: Dashboards for internet-of-things data or web traffic.
  * **Characteristics**: Few tables, often centering around a big table of device-, site- or user-events. High volume reads and writes, with relatively simple but computationally intensive lookups.

Distributing Data
=================

If your situation resembles either case above then the next step is to decide how to shard your data in the Citus cluster. As explained in :ref:`introduction_to_citus`, Citus assigns table rows to shards according to the hashed value of the table's distribution column. The database administrator's choice of distribution columns needs to match the access patterns of typical queries to ensure performance.

.. _distributing_by_tenant_id:

Multi-Tenant Apps
-----------------

The multi-tenant model as implemented in Citus allows applications to scale with minimal changes. This data model provides the performance characteristics of relational databases at scale. It also provides familiar benefits that come with relational databases, such as transactions, constraints, and joins. Once you follow the multi-tenant data model, it is easy to adjust a changing application while staying performant.

The multi-tenant architecture uses a form of hierarchical database modeling to distribute queries across nodes in the distributed cluster. The top of the data hierarchy is known as the *tenant id*, and needs to be stored in a column on each table. Citus inspects queries to see which tenant id they involve and routes the query to a single worker node for processing, specifically the node which holds the data shard associated with the tenant id. Running a query with all relevant data placed on the same node is called :ref:`colocation`.

The following diagram illustrates co-location in the multi-tenant data model. It contains two tables, Accounts and Campaigns, each distributed by :code:`account_id`. The shaded boxes represent shards, each of whose color represents which worker node contains it. Green shards are stored together on one worker node, and blue on another.  Notice how a join query between Accounts and Campaigns would have all the necessary data together on one node when restricting both tables to the same account_id.

.. figure:: ../images/mt-colocation.png
   :alt: co-located tables in multi-tenant architecture


To apply this design in your own schema the first step is identifying what constitutes a tenant in your application. Common instances include company, account, organization, or customer. The column name will be something like :code:`company_id` or :code:`customer_id`. Examine each of your queries and ask yourself: would it work if it had additional WHERE clauses to restrict all tables involved to rows with the same tenant id? Queries in the multi-tenant model are usually scoped to a tenant, for instance queries on sales or inventory would be scoped within a certain store.

If you're migrating an existing database to the Citus multi-tenant architecture then some of your tables may lack a column for the application-specific tenant id. You will need to add one and fill it with the correct values. This will denormalize your tables slightly. For more details and a concrete example of backfilling the tenant id, see our guide to :ref:`Multi-Tenant Migration <transitioning_mt>`.

.. _typical_mt_schema:

Typical Multi-Tenant Schema
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Most SaaS applications already have the notion of tenancy built into their data model. In the following, we will look at an example schema from the online advertising space. In this example, a web advertising platform has tenants that it refers to as accounts. Each account holds and tracks advertising clicks across various campaigns.

.. code-block:: postgres

  CREATE TABLE accounts (
    id bigint,
    name text NOT NULL,
    image_url text NOT NULL,

    PRIMARY KEY (id)
  );

  CREATE TABLE ads (
    id bigint,
    account_id bigint,
    campaign_id bigint,
    name text NOT NULL,
    image_url text NOT NULL,
    target_url text NOT NULL,
    impressions_count bigint DEFAULT 0 NOT NULL,
    clicks_count bigint DEFAULT 0 NOT NULL,

    PRIMARY KEY (account_id, id),
    FOREIGN KEY (account_id) REFERENCES accounts
  );

  CREATE TABLE clicks (
    id bigint,
    account_id bigint,
    ad_id bigint,
    clicked_at timestamp without time zone NOT NULL,
    site_url text NOT NULL,
    cost_per_click_usd numeric(20,10),
    user_ip inet NOT NULL,
    user_data jsonb NOT NULL,

    PRIMARY KEY (account_id, id),
    FOREIGN KEY (account_id) REFERENCES accounts,
    FOREIGN KEY (account_id, ad_id) REFERENCES ads (account_id, id)
  );

  SELECT create_distributed_table('accounts',  'id');
  SELECT create_distributed_table('ads',       'account_id');
  SELECT create_distributed_table('clicks',    'account_id');

Notice how the primary and foreign keys always contain the tenant id (in this case :code:`account_id`). Often this requires them to be compound keys. Enforcing key constraints is generally difficult in distributed databases. For Citus, the inclusion of the tenant id allows the database to push DML down to single nodes and successfully enforce the constraint.

Queries including a tenant id enable more than just key constraints. Such queries enjoy full SQL coverage in Citus, including JOINs, transactions, grouping, and aggregates. In the multi-tenant architecture, SQL queries that filter by tenant id work without modification, combining the familiarity of PostgreSQL with the power of horizontal scaling for large numbers of tenants.

Let's look at example queries that span some of these capabilities. First an analytical query to count newly arriving clicks per campaign for an arbitrary account, say account id=9700. Citus pushes this query down to the node containing tenant 9700 and executes it all in one place. Notice the tenant id is included in the join conditions.

.. code-block:: postgres

  SELECT ads.campaign_id, COUNT(*)
    FROM ads
    JOIN clicks c
      ON (ads.id = ad_id AND ads.account_id = c.account_id)
   WHERE ads.account_id = 9700
     AND clicked_at > now()::date
   GROUP BY ads.campaign_id;

What's more, Citus gives full ACID guarantees for single-tenant DML. The following query transactionally removes the record of a click (id = 12995) and decrements the click count cache for its associated ad. Notice we include a filter for :code:`account_id` on all the statements to ensure they affect the same tenant.

.. code-block:: sql

  BEGIN;

  -- get the ad id for later update
  SELECT ad_id
    FROM clicks
   WHERE id = 12995
     AND account_id = 9700;

  -- delete the click
  DELETE FROM clicks
   WHERE id = 12995
     AND account_id = 9700;

  -- decrement the ad click count for the ad we previously found
  UPDATE ads
     SET clicks_count = clicks_count - 1
   WHERE id = <the ad id>
     AND account_id = 9700;

  COMMIT;

We've seen some of the benefits of Citus for single-tenant queries, but it can also run and parallelize many kinds of queries across tenants, including aggregates. For instance, we can request the total clicks for ads by account:

.. code-block:: sql

  SELECT account_id, sum(clicks_count) AS total_clicks
    FROM ads GROUP BY account_id
  ORDER BY total_clicks DESC;

Citus is also able to seamlessly run DML statements on multiple tenants. As long as the update statement references data local to its own tenant it can be applied simultaneously to all tenants. Here is an example of modifying all image urls to use secure connections.

.. code-block:: sql

  UPDATE ads
  SET image_url = replace(
    image_url, 'http:', 'https:'
  );

.. _distributing_by_entity_id:

Real-Time Apps
--------------

While the multi-tenant architecture introduces a hierarchical structure and uses data co-location to parallelize queries between tenants, real-time architectures depend on specific distribution properties of their data to achieve highly parallel processing. We use "entity id" as a term for distribution columns in the real-time model, as opposed to tenant ids in the multi-tenant model. Typical entites are users, hosts, or devices.

Real-time queries typically ask for numeric aggregates grouped by date or category. Citus sends these queries to each shard for partial results and assembles the final answer on the coordinator node. Queries run fastest when as many nodes contribute as possible, and when no individual node bottlenecks.

The more evenly a choice of entity id distributes data to shards the better. At the least the column should have a high cardinality. For comparison, a "status" field on an order table is a poor choice of distribution column because it assumes at most a few values. These values will not be able to take advantage of a cluster with many shards. The row placement will skew into a small handful of shards:

.. image:: ../images/sharding-poorly-distributed.png

Of columns having high cardinality, it is good additionally to choose those that are frequently used in group-by clauses or as join keys. Distributing by join keys co-locates the joined tables and greatly improves join speed. Real-time schemas usually have few tables, and are generally centered around a big table of quantitative events.

Typical Real-Time Schemas
~~~~~~~~~~~~~~~~~~~~~~~~~

Events Table
^^^^^^^^^^^^

In this scenario we ingest high volume sensor measurement events into a single table and distribute it across Citus by the :code:`device_id` of the sensor. Every time the sensor makes a measurement we save that as a single event row with measurement details in a jsonb column for flexibility.

.. code-block:: postgres

  CREATE TABLE events (
    device_id bigint NOT NULL,
    event_id uuid NOT NULL,
    event_time timestamptz NOT NULL,
    event_type int NOT NULL,
    payload jsonb,
    PRIMARY KEY (device_id, event_id)
  );
  CREATE INDEX ON events USING BRIN (event_time);

  SELECT create_distributed_table('events', 'device_id');

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
    WHERE event_time >= now() - interval '10 minutes'
  ) ev
  GROUP BY minute
  ORDER BY minute ASC;

Events with Roll-Ups
^^^^^^^^^^^^^^^^^^^^

The previous example calculates statistics at runtime, doing possible recalculation between queries. Another approach is precalculating aggregates. This avoids recalculating raw event data and results in even faster queries. For example, a web analytics dashboard might want a count of views per page per day. The raw events data table looks like this:

.. code-block:: postgres

  CREATE TABLE page_views (
    page_id int PRIMARY KEY,
    host_ip inet,
    view_time timestamp default now()
  );
  CREATE INDEX view_time_idx ON page_views USING BRIN (view_time);

  SELECT create_distributed_table('page_views', 'page_id');

We will precompute the daily view count in this summary table:

.. code-block:: postgres

  CREATE TABLE daily_page_views (
    day date,
    page_id int,
    view_count bigint,
    PRIMARY KEY (day, page_id)
  );

  SELECT create_distributed_table('daily_page_views', 'page_id');

Precomputing aggregates is called *roll-up*. Notice that distributing both tables by :code:`page_id` co-locates their data per-page. Any aggregate functions grouped per page can run in parallel, and this includes aggregates in roll-ups. We can use PostgreSQL `UPSERT <https://www.postgresql.org/docs/current/static/sql-insert.html#SQL-ON-CONFLICT>`_ to create and update rollups, like this (the SQL below takes a parameter for the lower bound timestamp):

.. code-block:: postgres

  INSERT INTO daily_page_views (day, page_id, view_count)
  SELECT view_time::date AS day, page_id, count(*) AS view_count
  FROM page_views
  WHERE view_time >= $1
  GROUP BY view_time::date, page_id
  ON CONFLICT (day, page_id) DO UPDATE SET
    view_count = daily_page_views.view_count + EXCLUDED.view_count;

Events and Entities
^^^^^^^^^^^^^^^^^^^

Behavioral analytics seeks to understand users, from the website/product features they use to how they progress through funnels, to the effectiveness of marketing campaigns. Doing analysis tends to involve unforeseen factors which are uncovered by iterative experiments. It is hard to know initially what information about user activity will be relevant to future experiments, so analysts generally try to record everything they can. Using a distributed database like Citus allows them to query the accumulated data flexibly and quickly.

Let's look at a simplified example. Whereas the previous examples dealt with a single events table (possibly augmented with precomputed rollups), this one uses two main tables: users and their events. In particular, Wikipedia editors and their changes:

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

  SELECT create_distributed_table('wikipedia_editors', 'editor');
  SELECT create_distributed_table('wikipedia_changes', 'editor');

These tables can be populated by the Wikipedia API, and we can distribute them in Citus by the :code:`editor` column. Notice that this is a text column. Citus' hash distribution uses PostgreSQL hashing which supports a number of data types.

A co-located JOIN between editors and changes allows aggregates not only by editor, but by properties of an editor. For instance we can count the difference between the number of newly created pages by bot vs human. The grouping and counting is performed on worker nodes in parallel and the final results are merged on the coordinator node.

.. code-block:: postgres

  SELECT bot, count(*) AS pages_created
  FROM wikipedia_changes c,
       wikipedia_editors e
  WHERE c.editor = e.editor
    AND type = 'new'
  GROUP BY bot;

Events and Reference Tables
^^^^^^^^^^^^^^^^^^^^^^^^^^^

We've already seen how every row in a distributed table is stored on a shard. However for small tables there is a trick to achieve a kind of universal :ref:`co-location <colocation>`. We can choose to place all its rows into a single shard but replicate that shard to every worker node. It introduces storage and update costs of course, but this can be more than counterbalanced by the performance gains of read queries.

We call tables replicated to all nodes *reference tables.* They usually provide metadata about items in a larger table and are reminiscent of what data warehousing calls dimension tables.
