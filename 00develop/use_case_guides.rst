.. highlight:: postgresql

Use-Case Guides
###############


.. _mt_use_case:

Multi-tenant Applications
=========================

.. contents::

*Estimated read time: 30 minutes*

If you're building a Software-as-a-service (SaaS) application, you probably already have the notion of tenancy built into your data model. Typically, most information relates to tenants / customers / accounts and the database tables capture this natural relation.

For SaaS applications, each tenant's data can be stored together in a single database instance and kept isolated and invisible from other tenants. This is efficient in three ways. First application improvements apply to all clients. Second, sharing a database between tenants uses hardware efficiently. Last, it is much simpler to manage a single database for all tenants than a different database server for each tenant.

However, a single relational database instance has traditionally had trouble scaling to the volume of data needed for a large multi-tenant application. Developers were forced to relinquish the benefits of the relational model when data exceeded the capacity of a single database node.

Citus allows users to write multi-tenant applications as if they are connecting to a single PostgreSQL database, when in fact the database is a horizontally scalable cluster of machines. Client code requires minimal modifications and can continue to use full SQL capabilities.

This guide takes a sample multi-tenant application and describes how to model it for scalability with Citus. Along the way we examine typical challenges for multi-tenant applications like isolating tenants from noisy neighbors, scaling hardware to accommodate more data, and storing data that differs across tenants. PostgreSQL and Citus provide all the tools needed to handle these challenges, so let's get building.

Let's Make an App – Ad Analytics
--------------------------------

We'll build the back-end for an application that tracks online advertising performance and provides an analytics dashboard on top. It's a natural fit for a multi-tenant application because user requests for data concern one (their own) company at a time. Code for the full example application is `available <https://github.com/citusdata/citus-example-ad-analytics>`_ on Github.

Let's start by considering a simplified schema for this application. The application must keep track of multiple companies, each of which runs advertising campaigns. Campaigns have many ads, and each ad has associated records of its clicks and impressions.

Here is the example schema. We'll make some minor changes later, which allow us to effectively distribute and isolate the data in a distributed environment.

::

  CREATE TABLE companies (
    id bigserial PRIMARY KEY,
    name text NOT NULL,
    image_url text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
  );

  CREATE TABLE campaigns (
    id bigserial PRIMARY KEY,
    company_id bigint REFERENCES companies (id),
    name text NOT NULL,
    cost_model text NOT NULL,
    state text NOT NULL,
    monthly_budget bigint,
    blacklisted_site_urls text[],
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
  );

  CREATE TABLE ads (
    id bigserial PRIMARY KEY,
    campaign_id bigint REFERENCES campaigns (id),
    name text NOT NULL,
    image_url text,
    target_url text,
    impressions_count bigint DEFAULT 0,
    clicks_count bigint DEFAULT 0,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
  );

  CREATE TABLE clicks (
    id bigserial PRIMARY KEY,
    ad_id bigint REFERENCES ads (id),
    clicked_at timestamp without time zone NOT NULL,
    site_url text NOT NULL,
    cost_per_click_usd numeric(20,10),
    user_ip inet NOT NULL,
    user_data jsonb NOT NULL
  );

  CREATE TABLE impressions (
    id bigserial PRIMARY KEY,
    ad_id bigint REFERENCES ads (id),
    seen_at timestamp without time zone NOT NULL,
    site_url text NOT NULL,
    cost_per_impression_usd numeric(20,10),
    user_ip inet NOT NULL,
    user_data jsonb NOT NULL
  );

There are modifications we can make to the schema which will give it a performance boost in a distributed environment like Citus. To see how, we must become familiar with how Citus distributes data and executes queries.

Scaling the Relational Data Model
---------------------------------

The relational data model is great for applications. It protects data integrity, allows flexible queries, and accommodates changing data. Traditionally the only problem was that relational databases weren't considered capable of scaling to the workloads needed for big SaaS applications. Developers had to put up with NoSQL databases -- or a collection of backend services -- to reach that size.

With Citus you can keep your data model *and* make it scale. Citus appears to applications as a single PostgreSQL database, but it internally routes queries to an adjustable number of physical servers (nodes) which can process requests in parallel.

Multi-tenant applications have a nice property that we can take advantage of: queries usually always request information for one tenant at a time, not a mix of tenants. For instance, when a salesperson is searching prospect information in a CRM, the search results are specific to his employer; other businesses' leads and notes are not included.

Because application queries are restricted to a single tenant, such as a store or company, one approach for making multi-tenant application queries fast is to store *all* data for a given tenant on the same node. This minimizes network overhead between the nodes and allows Citus to support all your application's joins, key constraints and transactions efficiently. With this, you can scale across multiple nodes without having to totally re-write or re-architect your application.

.. image:: ../images/mt-ad-routing-diagram.png

We do this in Citus by making sure every table in our schema has a column to clearly mark which tenant owns which rows. In the ad analytics application the tenants are companies, so we must ensure all tables have a :code:`company_id` column.

We can tell Citus to use this column to read and write rows to the same node when the rows are marked for the same company. In Citus' terminology :code:`company_id` will be the *distribution column*, which you can learn more about in :ref:`Distributed Data Modeling <distributed_data_modeling>`.

Preparing Tables and Ingesting Data
-----------------------------------

In the previous section we identified the correct distribution column for our multi-tenant application: the company id. Even in a single-machine database it can be useful to denormalize tables with the addition of company id, whether it be for row-level security or for additional indexing. The extra benefit, as we saw, is that including the extra column helps for multi-machine scaling as well.

The schema we have created so far uses a separate :code:`id` column as primary key for each table. Citus requires that primary and foreign key constraints include the distribution column. This requirement makes enforcing these constraints much more efficient in a distributed environment as only a single node has to be checked to guarantee them.

In SQL, this requirement translates to making primary and foreign keys composite by including :code:`company_id`. This is compatible with the multi-tenant case because what we really need there is to ensure uniqueness on a per-tenant basis.

Putting it all together, here are the changes which prepare the tables for distribution by :code:`company_id`.

::

  CREATE TABLE companies (
    id bigserial PRIMARY KEY,
    name text NOT NULL,
    image_url text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
  );

  CREATE TABLE campaigns (
    id bigserial,       -- was: PRIMARY KEY
    company_id bigint REFERENCES companies (id),
    name text NOT NULL,
    cost_model text NOT NULL,
    state text NOT NULL,
    monthly_budget bigint,
    blacklisted_site_urls text[],
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    PRIMARY KEY (company_id, id) -- added
  );

  CREATE TABLE ads (
    id bigserial,       -- was: PRIMARY KEY
    company_id bigint,  -- added
    campaign_id bigint, -- was: REFERENCES campaigns (id)
    name text NOT NULL,
    image_url text,
    target_url text,
    impressions_count bigint DEFAULT 0,
    clicks_count bigint DEFAULT 0,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    PRIMARY KEY (company_id, id),         -- added
    FOREIGN KEY (company_id, campaign_id) -- added
      REFERENCES campaigns (company_id, id)
  );

  CREATE TABLE clicks (
    id bigserial,        -- was: PRIMARY KEY
    company_id bigint,   -- added
    ad_id bigint,        -- was: REFERENCES ads (id),
    clicked_at timestamp without time zone NOT NULL,
    site_url text NOT NULL,
    cost_per_click_usd numeric(20,10),
    user_ip inet NOT NULL,
    user_data jsonb NOT NULL,
    PRIMARY KEY (company_id, id),      -- added
    FOREIGN KEY (company_id, ad_id)    -- added
      REFERENCES ads (company_id, id)
  );

  CREATE TABLE impressions (
    id bigserial,         -- was: PRIMARY KEY
    company_id bigint,    -- added
    ad_id bigint,         -- was: REFERENCES ads (id),
    seen_at timestamp without time zone NOT NULL,
    site_url text NOT NULL,
    cost_per_impression_usd numeric(20,10),
    user_ip inet NOT NULL,
    user_data jsonb NOT NULL,
    PRIMARY KEY (company_id, id),       -- added
    FOREIGN KEY (company_id, ad_id)     -- added
      REFERENCES ads (company_id, id)
  );

You can learn more about migrating your own data model in :ref:`multi-tenant schema migration <mt_schema_migration>`.

Try it Yourself
~~~~~~~~~~~~~~~

.. note::

  This guide is designed so you can follow along in your own Citus database. Use one of these alternatives to spin up a database:

  * Run Citus locally using :ref:`single_machine_docker`, or
  * Provision a cluster using `Citus Cloud <https://console.citusdata.com/users/sign_up>`_

  You'll run the SQL commands using psql:

  * **Docker**: :code:`docker exec -it citus_master psql -U postgres`
  * **Cloud**: :code:`psql "connection-string"` where the connection string for your formation is available in the Cloud Console.

  In either case psql will be connected to the coordinator node for the cluster.

At this point feel free to follow along in your own Citus cluster by `downloading <https://examples.citusdata.com/mt_ref_arch/schema.sql>`_ and executing the SQL to create the schema. Once the schema is ready, we can tell Citus to create shards on the workers. From the coordinator node, run:

::

  SELECT create_distributed_table('companies',   'id');
  SELECT create_distributed_table('campaigns',   'company_id');
  SELECT create_distributed_table('ads',         'company_id');
  SELECT create_distributed_table('clicks',      'company_id');
  SELECT create_distributed_table('impressions', 'company_id');

The :ref:`create_distributed_table` function informs Citus that a table should be distributed among nodes and that future incoming queries to those tables should be planned for distributed execution. The function also creates shards for the table on worker nodes, which are low-level units of data storage Citus uses to assign data to nodes.

The next step is loading sample data into the cluster from the command line.

.. code-block:: bash

  # download and ingest datasets from the shell

  for dataset in companies campaigns ads clicks impressions geo_ips; do
    curl -O https://examples.citusdata.com/mt_ref_arch/${dataset}.csv
  done

.. note::

  **If you are using Docker,** you should use the :code:`docker cp` command to copy the files into the Docker container.

  .. code-block:: bash

    for dataset in companies campaigns ads clicks impressions geo_ips; do
      docker cp ${dataset}.csv citus_master:.
    done

Being an extension of PostgreSQL, Citus supports bulk loading with the COPY command. Use it to ingest the data you downloaded, and make sure that you specify the correct file path if you downloaded the file to some other location. Back inside psql run this:

.. code-block:: text

  \copy companies from 'companies.csv' with csv
  \copy campaigns from 'campaigns.csv' with csv
  \copy ads from 'ads.csv' with csv
  \copy clicks from 'clicks.csv' with csv
  \copy impressions from 'impressions.csv' with csv

Integrating Applications
------------------------

Here's the good news: once you have made the slight schema modification outlined earlier, your application can scale with very little work. You'll just connect the app to Citus and let the database take care of keeping the queries fast and the data safe.

Any application queries or update statements which include a filter on :code:`company_id` will continue to work exactly as they are. As mentioned earlier, this kind of filter is common in multi-tenant apps. When using an Object-Relational Mapper (ORM) you can recognize these queries by methods such as :code:`where` or :code:`filter`.

ActiveRecord:

.. code-block:: ruby

  Impression.where(company_id: 5).count

Django:

.. code-block:: py

  Impression.objects.filter(company_id=5).count()

Basically when the resulting SQL executed in the database contains a :code:`WHERE company_id = :value` clause on every table (including tables in JOIN queries), then Citus will recognize that the query should be routed to a single node and execute it there as it is. This makes sure that all SQL functionality is available. The node is an ordinary PostgreSQL server after all.

Also, to make it even simpler, you can use our `activerecord-multi-tenant <https://github.com/citusdata/activerecord-multi-tenant>`_ library for Rails, or `django-multitenant <https://github.com/citusdata/django-multitenant>`_ for Django which will automatically add these filters to all your queries, even the complicated ones. Check out our :ref:`app_migration` section for details.

This guide is framework-agnostic, so we'll point out some Citus features using SQL. Use your imagination for how these statements would be expressed in your language of choice.

Here is a simple query and update operating on a single tenant.

::

  -- campaigns with highest budget

  SELECT name, cost_model, state, monthly_budget
    FROM campaigns
   WHERE company_id = 5
   ORDER BY monthly_budget DESC
   LIMIT 10;

  -- double the budgets!

  UPDATE campaigns
     SET monthly_budget = monthly_budget*2
   WHERE company_id = 5;

A common pain point for users scaling applications with NoSQL databases is the lack of transactions and joins. However, transactions work as you'd expect them to in Citus:

::

  -- transactionally reallocate campaign budget money

  BEGIN;

  UPDATE campaigns
     SET monthly_budget = monthly_budget + 1000
   WHERE company_id = 5
     AND id = 40;

  UPDATE campaigns
     SET monthly_budget = monthly_budget - 1000
   WHERE company_id = 5
     AND id = 41;

  COMMIT;

As a final demo of SQL support, we have a query which includes aggregates and window functions and it works the same in Citus as it does in PostgreSQL. The query ranks the ads in each campaign by the count of their impressions.

::

  SELECT a.campaign_id,
         RANK() OVER (
           PARTITION BY a.campaign_id
           ORDER BY a.campaign_id, count(*) desc
         ), count(*) as n_impressions, a.id
    FROM ads as a,
         impressions as i
   WHERE a.company_id = 5
     AND i.company_id = a.company_id
     AND i.ad_id      = a.id
  GROUP BY a.campaign_id, a.id
  ORDER BY a.campaign_id, n_impressions desc;

In short when queries are scoped to a tenant then inserts, updates, deletes, complex SQL, and transactions all work as expected.

.. _mt_ref_tables:

Sharing Data Between Tenants
----------------------------

Up until now all tables have been distributed by :code:`company_id`, but sometimes there is data that can be shared by all tenants, and doesn't "belong" to any tenant in particular. For instance, all companies using this example ad platform might want to get geographical information for their audience based on IP addresses. In a single machine database this could be accomplished by a lookup table for geo-ip, like the following. (A real table would probably use PostGIS but bear with the simplified example.)

::

  CREATE TABLE geo_ips (
    addrs cidr NOT NULL PRIMARY KEY,
    latlon point NOT NULL
      CHECK (-90  <= latlon[0] AND latlon[0] <= 90 AND
             -180 <= latlon[1] AND latlon[1] <= 180)
  );
  CREATE INDEX ON geo_ips USING gist (addrs inet_ops);

To use this table efficiently in a distributed setup, we need to find a way to co-locate the :code:`geo_ips` table with clicks for not just one -- but every -- company. That way, no network traffic need be incurred at query time. We do this in Citus by designating :code:`geo_ips` as a :ref:`reference table <reference_tables>`.

::

  -- Make synchronized copies of geo_ips on all workers

  SELECT create_reference_table('geo_ips');

Reference tables are replicated across all worker nodes, and Citus automatically keeps them in sync during modifications. Notice that we call :ref:`create_reference_table <create_reference_table>` rather than :code:`create_distributed_table`.

Now that :code:`geo_ips` is established as a reference table, load it with example data:

.. code-block:: psql

  \copy geo_ips from 'geo_ips.csv' with csv

Now joining clicks with this table can execute efficiently. We can ask, for example, the locations of everyone who clicked on ad 290.

::

  SELECT c.id, clicked_at, latlon
    FROM geo_ips, clicks c
   WHERE addrs >> c.user_ip
     AND c.company_id = 5
     AND c.ad_id = 290;

Online Changes to the Schema
----------------------------

Another challenge with multi-tenant systems is keeping the schemas for all the tenants in sync. Any schema change needs to be consistently reflected across all the tenants. In Citus, you can simply use standard PostgreSQL DDL commands to change the schema of your tables, and Citus will propagate them from the coordinator node to the workers using a two-phase commit protocol.

For example, the advertisements in this application could use a text caption. We can add a column to the table by issuing the standard SQL on the coordinator:

::

  ALTER TABLE ads
    ADD COLUMN caption text;

This updates all the workers as well. Once this command finishes, the Citus cluster will accept queries that read or write data in the new :code:`caption` column.

For a fuller explanation of how DDL commands propagate through the cluster, see :ref:`ddl_prop_support`.

When Data Differs Across Tenants
--------------------------------

Given that all tenants share a common schema and hardware infrastructure, how can we accommodate tenants which want to store information not needed by others? For example, one of the tenant applications using our advertising database may want to store tracking cookie information with clicks, whereas another tenant may care about browser agents. Traditionally databases using a shared schema approach for multi-tenancy have resorted to creating a fixed number of pre-allocated "custom" columns, or having external "extension tables." However PostgreSQL provides a much easier way with its unstructured column types, notably `JSONB <https://www.postgresql.org/docs/current/static/datatype-json.html>`_.

Notice that our schema already has a JSONB field in :code:`clicks` called :code:`user_data`. Each tenant can use it for flexible storage.

Suppose company five includes information in the field to track whether the user is on a mobile device. The company can query to find who clicks more, mobile or traditional visitors:

.. code-block:: postgresql

  SELECT
    user_data->>'is_mobile' AS is_mobile,
    count(*) AS count
  FROM clicks
  WHERE company_id = 5
  GROUP BY user_data->>'is_mobile'
  ORDER BY count DESC;

The database administrator can even create a `partial index <https://www.postgresql.org/docs/current/static/indexes-partial.html>`_ to improve speed for an individual tenant's query patterns. Here is one to improve company 5's filters for clicks from users on mobile devices:

.. code-block:: postgresql

  CREATE INDEX click_user_data_is_mobile
  ON clicks ((user_data->>'is_mobile'))
  WHERE company_id = 5;

Additionally, PostgreSQL supports `GIN indices <https://www.postgresql.org/docs/current/static/gin-intro.html>`_ on JSONB. Creating a GIN index on a JSONB column will create an index on every key and value within that JSON document. This speeds up a number of `JSONB operators <https://www.postgresql.org/docs/current/static/functions-json.html#FUNCTIONS-JSONB-OP-TABLE>`_ such as :code:`?`, :code:`?|`, and :code:`?&`.

.. code-block:: postgresql

  CREATE INDEX click_user_data
  ON clicks USING gin (user_data);

  -- this speeds up queries like, "which clicks have
  -- the is_mobile key present in user_data?"

  SELECT id
    FROM clicks
   WHERE user_data ? 'is_mobile'
     AND company_id = 5;

Scaling Hardware Resources
--------------------------

.. note::

  This section uses features available only in `Citus Cloud <https://www.citusdata.com/product/cloud>`_ and `Citus Enterprise <https://www.citusdata.com/product/enterprise>`_. Also, please note that these features are available in Citus Cloud across all plans except for the "Dev Plan".

Multi-tenant databases should be designed for future scale as business grows or tenants want to store more data. Citus can scale out easily by adding new machines without having to make any changes or take application downtime.

Being able to rebalance data in the Citus cluster allows you to grow your data size or number of customers and improve performance on demand. Adding new machines allows you to keep data in memory even when it is much larger than what a single machine can store.

Also, if data increases for only a few large tenants, then you can isolate those particular tenants to separate nodes for better performance.

To scale out your Citus cluster, first add a new worker node to it. On Citus Cloud, you can use the slider present in the "Settings" tab, sliding it to add the required number of nodes. Alternately, if you run your own Citus installation, you can add nodes manually with the :ref:`master_add_node` UDF.

.. image:: ../images/cloud-nodes-slider.png

Once you add the node it will be available in the system. However at this point no tenants are stored on it and Citus will not yet run any queries there. To move your existing data, you can ask Citus to rebalance the data. This operation moves bundles of rows called shards between the currently active nodes to attempt to equalize the amount of data on each node.

.. code-block:: postgres

  SELECT rebalance_table_shards('companies');

Rebalancing preserves :ref:`colocation`, which means we can tell Citus to rebalance the companies table and it will take the hint and rebalance the other tables which are distributed by company_id. Also, applications do not need to undergo downtime during shard rebalancing. Read requests continue seamlessly, and writes are locked only when they affect shards which are currently in flight.

You can learn more about how shard rebalancing works here: :ref:`scaling_out`.


Dealing with Big Tenants
------------------------

.. note::

  This section uses features available only in Citus Cloud and Citus Enterprise.

The previous section describes a general-purpose way to scale a cluster as the number of tenants increases. However, users often have two questions. The first is what will happen to their largest tenant if it grows too big. The second is what are the performance implications of hosting a large tenant together with small ones on a single worker node, and what can be done about it.

Regarding the first question, investigating data from large SaaS sites reveals that as the number of tenants increases, the size of tenant data typically tends to follow a `Zipfian distribution <https://en.wikipedia.org/wiki/Zipf%27s_law>`_.

.. image:: ../images/zipf.png

For instance, in a database of 100 tenants, the largest is predicted to account for about 20% of the data. In a more realistic example for a large SaaS company, if there are 10k tenants, the largest will account for around 2% of the data. Even at 10TB of data, the largest tenant will require 200GB, which can pretty easily fit on a single node.

Another question is regarding performance when large and small tenants are on the same node. Standard shard rebalancing will improve overall performance but it may or may not improve the mixing of large and small tenants. The rebalancer simply distributes shards to equalize storage usage on nodes, without examining which tenants are allocated on each shard.

To improve resource allocation and make guarantees of tenant QoS it is worthwhile to move large tenants to dedicated nodes. Citus provides the tools to do this.

In our case, let's imagine that our old friend company id=5 is very large. We can isolate the data for this tenant in two steps. We'll present the commands here, and you can consult :ref:`tenant_isolation` to learn more about them.

First sequester the tenant's data into a bundle (called a shard) suitable to move. The CASCADE option also applies this change to the rest of our tables distributed by :code:`company_id`.

::


  SELECT isolate_tenant_to_new_shard(
    'companies', 5, 'CASCADE'
  );

The output is the shard id dedicated to hold :code:`company_id=5`:

.. code-block:: text

  ┌─────────────────────────────┐
  │ isolate_tenant_to_new_shard │
  ├─────────────────────────────┤
  │                      102240 │
  └─────────────────────────────┘

Next we move the data across the network to a new dedicated node. Create a new node as described in the previous section. Take note of its hostname as shown in the Nodes tab of the Cloud Console.

::

  -- find the node currently holding the new shard

  SELECT nodename, nodeport
    FROM pg_dist_placement AS placement,
         pg_dist_node AS node
   WHERE placement.groupid = node.groupid
     AND node.noderole = 'primary'
     AND shardid = 102240;

  -- move the shard to your choice of worker (it will also move the
  -- other shards created with the CASCADE option)

  SELECT master_move_shard_placement(
    102240,
    'source_host', source_port,
    'dest_host', dest_port);

You can confirm the shard movement by querying :ref:`pg_dist_placement <placements>` again.

Where to Go From Here
---------------------

With this, you now know how to use Citus to power your multi-tenant application for scalability. If you have an existing schema and want to migrate it for Citus, see :ref:`Multi-Tenant Transitioning <transitioning_mt>`.

To adjust a front-end application, specifically Ruby on Rails or Django, read :ref:`rails_migration`. Finally, try :ref:`Citus Cloud <cloud_overview>`, the easiest way to manage a Citus cluster, available with discounted developer plan pricing.

.. _rt_use_case:

Real Time Dashboards
====================

Citus provides real-time queries over large datasets. One workload we commonly see at
Citus involves powering real-time dashboards of event data.

For example, you could be a cloud services provider helping other businesses monitor their
HTTP traffic. Every time one of your clients receives an HTTP request your service
receives a log record. You want to ingest all those records and create an HTTP analytics
dashboard which gives your clients insights such as the number HTTP errors their sites
served. It's important that this data shows up with as little latency as possible so your
clients can fix problems with their sites. It's also important for the dashboard to show
graphs of historical trends.

Alternatively, maybe you're building an advertising network and want to show clients
clickthrough rates on their campaigns. In this example latency is also critical, raw data
volume is also high, and both historical and live data are important.

In this section we'll demonstrate how to build part of the first example, but this
architecture would work equally well for the second and many other use-cases.

Data Model
----------

The data we're dealing with is an immutable stream of log data. We'll insert directly into
Citus but it's also common for this data to first be routed through something like Kafka.
Doing so has the usual advantages, and makes it easier to pre-aggregate the data once data
volumes become unmanageably high.

We'll use a simple schema for ingesting HTTP event data. This schema serves as an example
to demonstrate the overall architecture; a real system might use additional columns.

.. code-block:: sql

  -- this is run on the coordinator

  CREATE TABLE http_request (
    site_id INT,
    ingest_time TIMESTAMPTZ DEFAULT now(),

    url TEXT,
    request_country TEXT,
    ip_address TEXT,

    status_code INT,
    response_time_msec INT
  );

  SELECT create_distributed_table('http_request', 'site_id');

When we call :ref:`create_distributed_table <create_distributed_table>`
we ask Citus to hash-distribute ``http_request`` using the ``site_id`` column. That means
all the data for a particular site will live in the same shard.

The UDF uses the default configuration values for shard count. We
recommend :ref:`using 2-4x as many shards <faq_choose_shard_count>` as
CPU cores in your cluster. Using this many shards lets you rebalance
data across your cluster after adding new worker nodes.

.. NOTE::

  Citus Cloud uses `streaming replication <https://www.postgresql.org/docs/current/static/warm-standby.html>`_ to achieve high availability and thus maintaining shard replicas would be redundant. In any production environment where streaming replication is unavailable, you should set ``citus.shard_replication_factor`` to 2 or higher for fault tolerance.

With this, the system is ready to accept data and serve queries! Keep the following loop running in a ``psql`` console in the background while you continue with the other commands in this article. It generates fake data every second or two.

.. code-block:: postgres

  DO $$
    BEGIN LOOP
      INSERT INTO http_request (
        site_id, ingest_time, url, request_country,
        ip_address, status_code, response_time_msec
      ) VALUES (
        trunc(random()*32), clock_timestamp(),
        concat('http://example.com/', md5(random()::text)),
        ('{China,India,USA,Indonesia}'::text[])[ceil(random()*4)],
        concat(
          trunc(random()*250 + 2), '.',
          trunc(random()*250 + 2), '.',
          trunc(random()*250 + 2), '.',
          trunc(random()*250 + 2)
        )::inet,
        ('{200,404}'::int[])[ceil(random()*2)],
        5+trunc(random()*150)
      );
      PERFORM pg_sleep(random() * 0.25);
    END LOOP;
  END $$;

Once you're ingesting data, you can run dashboard queries such as:

.. code-block:: sql

  SELECT
    site_id,
    date_trunc('minute', ingest_time) as minute,
    COUNT(1) AS request_count,
    SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
    SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
  FROM http_request
  WHERE date_trunc('minute', ingest_time) > now() - '5 minutes'::interval
  GROUP BY site_id, minute
  ORDER BY minute ASC;

The setup described above works, but has two drawbacks:

* Your HTTP analytics dashboard must go over each row every time it needs to generate a
  graph. For example, if your clients are interested in trends over the past year, your
  queries will aggregate every row for the past year from scratch.
* Your storage costs will grow proportionally with the ingest rate and the length of the
  queryable history. In practice, you may want to keep raw events for a shorter period of
  time (one month) and look at historical graphs over a longer time period (years).

Rollups
-------

You can overcome both drawbacks by rolling up the raw data into a pre-aggregated form.
Here, we'll aggregate the raw data into a table which stores summaries of 1-minute
intervals. In a production system, you would probably also want something like 1-hour and
1-day intervals, these each correspond to zoom-levels in the dashboard. When the user
wants request times for the last month the dashboard can simply read and chart the values
for each of the last 30 days.

.. code-block:: sql

  CREATE TABLE http_request_1min (
    site_id INT,
    ingest_time TIMESTAMPTZ, -- which minute this row represents

    error_count INT,
    success_count INT,
    request_count INT,
    average_response_time_msec INT,
    CHECK (request_count = error_count + success_count),
    CHECK (ingest_time = date_trunc('minute', ingest_time))
  );

  SELECT create_distributed_table('http_request_1min', 'site_id');

  CREATE INDEX http_request_1min_idx ON http_request_1min (site_id, ingest_time);

This looks a lot like the previous code block. Most importantly: It also shards on
``site_id`` and uses the same default configuration for shard count and
replication factor. Because all three of those match, there's a 1-to-1
correspondence between ``http_request`` shards and ``http_request_1min`` shards,
and Citus will place matching shards on the same worker. This is called
:ref:`co-location <colocation>`; it makes queries such as joins faster and our rollups possible.

.. image:: /images/colocation.png
  :alt: co-location in citus

In order to populate ``http_request_1min`` we're going to periodically run
an INSERT INTO SELECT. This is possible because the tables are co-located.
The following function wraps the rollup query up for convenience.

.. code-block:: plpgsql

  CREATE OR REPLACE FUNCTION rollup_http_request() RETURNS void AS $$
  BEGIN
    INSERT INTO http_request_1min (
      site_id, ingest_time, request_count,
      success_count, error_count, average_response_time_msec
    ) SELECT
      site_id,
      minute,
      COUNT(1) as request_count,
      SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
      SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
      SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
    FROM (
      SELECT *,
        date_trunc('minute', ingest_time) AS minute
      FROM http_request
    ) AS h
    WHERE minute > (
      SELECT COALESCE(max(ingest_time), timestamp '10-10-1901')
      FROM http_request_1min
      WHERE http_request_1min.site_id = h.site_id
    )
      AND minute <= date_trunc('minute', now())
    GROUP BY site_id, minute
    ORDER BY minute ASC;
  END;
  $$ LANGUAGE plpgsql;

.. note::

  The above function should be called every minute. You could do this by
  adding a crontab entry on the coordinator node:

  .. code-block:: bash

    * * * * * psql -c 'SELECT rollup_http_request();'

  Alternately, an extension such as `pg_cron <https://github.com/citusdata/pg_cron>`_
  allows you to schedule recurring queries directly from the database.

The dashboard query from earlier is now a lot nicer:

.. code-block:: sql

  SELECT site_id, ingest_time as minute, request_count,
         success_count, error_count, average_response_time_msec
    FROM http_request_1min
   WHERE ingest_time > date_trunc('minute', now()) - '5 minutes'::interval;

Expiring Old Data
-----------------

The rollups make queries faster, but we still need to expire old data to avoid unbounded
storage costs. Simply decide how long you'd like to keep data for each granularity, and use standard queries to delete expired data. In the following example, we decided to
keep raw data for one day, and per-minute aggregations for one month:

.. code-block:: plpgsql

  DELETE FROM http_request WHERE ingest_time < now() - interval '1 day';
  DELETE FROM http_request_1min WHERE ingest_time < now() - interval '1 month';

In production you could wrap these queries in a function and call it every minute in a cron job.

Data expiration can go even faster by using table range partitioning on top of Citus hash distribution. See the :ref:`timeseries` section for a detailed example.

Those are the basics! We provided an architecture that ingests HTTP events and
then rolls up these events into their pre-aggregated form. This way, you can both store
raw events and also power your analytical dashboards with subsecond queries.


The next sections extend upon the basic architecture and show you how to resolve questions
which often appear.


Approximate Distinct Counts
---------------------------

A common question in HTTP analytics deals with :ref:`approximate distinct counts
<count_distinct>`: How many unique visitors visited your site over the last month?
Answering this question *exactly* requires storing the list of all previously-seen visitors
in the rollup tables, a prohibitively large amount of data. However an approximate answer
is much more manageable.

A datatype called hyperloglog, or HLL, can answer the query
approximately; it takes a surprisingly small amount of space to tell you
approximately how many unique elements are in a set. Its accuracy can be
adjusted. We'll use ones which, using only 1280 bytes, will be able to
count up to tens of billions of unique visitors with at most 2.2% error.

An equivalent problem appears if you want to run a global query, such as the number of
unique IP addresses which visited any of your client's sites over the last month. Without
HLLs this query involves shipping lists of IP addresses from the workers to the coordinator for
it to deduplicate. That's both a lot of network traffic and a lot of computation. By using
HLLs you can greatly improve query speed.

First you must install the HLL extension; `the github repo
<https://github.com/citusdata/postgresql-hll>`_ has instructions. Next, you have
to enable it:

.. code-block:: sql

  --------------------------------------------------------
  -- Run on all nodes ------------------------------------

  CREATE EXTENSION hll;

  -- allow SUM to work on hashvals (alias for hll_add_agg)
  CREATE AGGREGATE sum(hll_hashval) (
    SFUNC = hll_add_trans0,
    STYPE = internal,
    FINALFUNC = hll_pack
  );

.. note::

  This is not necessary on Citus Cloud, which has HLL already installed,
  along with other useful :ref:`cloud_extensions`.

Now we're ready to track IP addresses in our rollup with HLL. First
add a column to the rollup table.

.. code-block:: sql

  ALTER TABLE http_request_1min ADD COLUMN distinct_ip_addresses hll;

Next use our custom aggregation to populate the column. Just add it
to the query in our rollup function:

.. code-block:: diff

  @@ -1,10 +1,12 @@
    INSERT INTO http_request_1min (
      site_id, ingest_time, request_count,
      success_count, error_count, average_response_time_msec,
  +   distinct_ip_addresses
    ) SELECT
      site_id,
      minute,
      COUNT(1) as request_count,
      SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
      SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
      SUM(response_time_msec) / COUNT(1) AS average_response_time_msec,
  +   SUM(hll_hash_text(ip_address)) AS distinct_ip_addresses
    FROM (

Dashboard queries are a little more complicated, you have to read out the distinct
number of IP addresses by calling the ``hll_cardinality`` function:

.. code-block:: sql

  SELECT site_id, ingest_time as minute, request_count,
         success_count, error_count, average_response_time_msec,
         hll_cardinality(distinct_ip_addresses) AS distinct_ip_address_count
    FROM http_request_1min
   WHERE ingest_time > date_trunc('minute', now()) - interval '5 minutes';

HLLs aren't just faster, they let you do things you couldn't previously. Say we did our
rollups, but instead of using HLLs we saved the exact unique counts. This works fine, but
you can't answer queries such as "how many distinct sessions were there during this
one-week period in the past we've thrown away the raw data for?".

With HLLs, this is easy. You'll first need to inform Citus about the ``hll_union_agg``
aggregate function and its semantics. You do this by running the following:

.. code-block:: sql

  --------------------------------------------------------
  -- Run on all nodes ------------------------------------

  -- (not necessary on Citus Cloud)

  CREATE AGGREGATE sum (hll)
  (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
  );


Now, when you call SUM over a collection of HLLs, PostgreSQL will return the HLL for us.
You can then compute distinct IP counts over a time period with the following query:

.. code-block:: sql

  SELECT hll_cardinality(SUM(distinct_ip_addresses))
  FROM http_request_1min
  WHERE ingest_time > date_trunc('minute', now()) - '5 minutes'::interval;

You can find more information on HLLs `in the project's GitHub repository
<https://github.com/aggregateknowledge/postgresql-hll>`_.

Unstructured Data with JSONB
----------------------------

Citus works well with Postgres' built-in support for unstructured data types. To
demonstrate this, let's keep track of the number of visitors which came from each country.
Using a semi-structure data type saves you from needing to add a column for every
individual country and ending up with rows that have hundreds of sparsely filled columns.
We have `a blog post
<https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_ explaining
which format to use for your semi-structured data. The post recommends JSONB, here we'll
demonstrate how to incorporate JSONB columns into your data model.

First, add the new column to our rollup table:

.. code-block:: sql

  ALTER TABLE http_request_1min ADD COLUMN country_counters JSONB;

Next, include it in the rollups by modifying the rollup function:

.. code-block:: diff

  @@ -1,14 +1,19 @@
   INSERT INTO http_request_1min (
     site_id, ingest_time, request_count,
     success_count, error_count, average_response_time_msec,
  +  country_counters
   ) SELECT
     site_id,
     minute,
     COUNT(1) as request_count,
     SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_c
     SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_cou
     SUM(response_time_msec) / COUNT(1) AS average_response_time_msec,
  +  jsonb_object_agg(request_country, country_count) AS country_counters
   FROM (
     SELECT *,
       date_trunc('minute', ingest_time) AS minute,
  +    count(1) OVER (
  +      PARTITION BY site_id, date_trunc('minute', ingest_time), request_country
  +    ) AS country_count
     FROM http_request

Now, if you want to get the number of requests which came from America in your dashboard,
your can modify the dashboard query to look like this:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    COALESCE(country_counters->>'USA', '0')::int AS american_visitors
  FROM http_request_1min
  WHERE ingest_time > date_trunc('minute', now()) - '5 minutes'::interval;

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'real-time', section: 'ref'});
  </script>
