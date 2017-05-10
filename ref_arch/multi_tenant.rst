.. highlight:: postgresql

Multi-tenant Applications
#########################

.. contents::

*Estimated read time: 30 minutes*

Many companies with web applications cater not to end users, but to other businesses with customers of their own. When many clients with similar needs are expected, it makes sense to run a single instance of the application to handle all the clients.

A software-as-a-service (SaaS) provider, for example, can run one instance of its application on one instance of a database and provide web access to multiple customers. In such a scenario, each tenant's data is isolated and remains invisible to other tenants. This is efficient in two ways. First application improvements apply to all clients. Second, sharing a database between tenants uses hardware efficiently.

Using Citus, multi-tenant applications can be written as if they are connecting to a single PostgreSQL database, when in fact the database is a horizontally scalable cluster of machines. Client code requires minimal modifications and can continue to use full SQL capabilities.

This guide takes an example multi-tenant database schema and adjusts it for use in Citus. Along the way we examine typical challenges for multi-tenant applications like per-tenant customization, isolating tenants from noisy neighbors, and scaling hardware to accomodate more data. PostgreSQL and Citus provide the tools to handle these challenges, so let's get building.

Let's Make an App: Ad Analytics
-------------------------------

We'll build the backend for an application that tracks online advertising performance and provides an analytics dashboard on top. It's a natural fit for a multi-tenant SaaS application because each company running ad campaigns is concerned with the performance of only its own ads. The queries' requests for data are partitioned per company.

Before jumping ahead to all that, let's consider a simplified schema for this application, designed for use on a single-machine PostgreSQL database. The application must keep track of multiple companies, each of which runs advertising campaigns. Campaigns have many ads, and each ad has associated records of its clicks and impressions.

.. note::

  This guide is designed so you can follow along in your own Citus database. Use one of these alternatives to spin up a database:

  * Run Citus locally using :ref:`single_machine_docker`, or
  * Provision a cluster using `Citus Cloud <https://console.citusdata.com/users/sign_up>`_

  You'll run the SQL commands using psql:

  * **Docker**: :code:`docker exec -it citus_master psql -U postgres`
  * **Cloud**: :code:`psql "connection-string"` where the connection string for your formation is available in the Cloud Console.

Here is the initial schema for our application. Feel free to run this code in your own Citus database.

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

  CREATE TABLE geo_ips (
    ip inet NOT NULL PRIMARY KEY,
    latlon point NOT NULL
      CHECK (-90  <= latlon[0] AND latlon[0] <= 90 AND
             -180 <= latlon[1] AND latlon[1] <= 180)
  );

This schema supports querying the performance of ads and campaigns. It is designed for a single-machine database, and will require adjustment in a distributed environment. To see why, we must become familar with how Citus distributes data and executes queries.

Applications connect to a certain PostgreSQL server in the Citus cluster called the *coordinator node.* The connection is established using an ordinary PostgreSQL `connection URI <https://www.postgresql.org/docs/current/static/libpq-connect.html#AEN45527>`_. However the actual data and processing is stored on and will happen in other machines called *worker nodes.*

The coordinator examines each client query and determines what data the query needs, and which worker nodes have the data. The coordinator then splits the query into simplified *query fragments*, and sends them to worker nodes for processing. When the workers' results are ready, the coordinator puts them together into a final result and forwards it to the application.

DIAGRAM: diagram of query execution

Distributing Data
-----------------

Using Citus effectively requires choosing the right pattern for distributing data and doing processing across workers. Citus runs fastest when the data distribution maximizes worker parallelism and minimizes network overhead for the application's most common queries. To minimize network overhead, related data items should be stored together on the same worker node. In multi-tenant applications this means that all data for a given tenant should be stored on the same worker. (Multiple tenants can be stored on the same worker for better hardware utilization, but no single tenant's data should span multiple workers.)

Citus stores rows in groups called *shards*, where each shard is placed on a worker node. The bundling of rows into shards is determined by the value of a special column in each table called the *distribution column*. (This column is chosen by the database administrator for each table.) When reading or writing a row in a distributed table, Citus hashes the value in the the row's distribution column and compares it against the range of hashed values accepted by each shard. The shard hash ranges are disjoint and span the hash space. In short, Citus accesses a row by hashing its distribution column, finding the shard whose range includes the hashed value, and deferring to the worker node where the shard is placed.

DIAGRAM: image of shards and their ranges

Returning to the ad analytics application, let's consider the options for choosing distribution columns for the tables, and the consequences of our choice. The performance of Citus must be evaluated in terms of specific queries. Consider a simple query to find the top campaigns with highest budget for a given company.

::

  -- Top ten campaigns with highest budget for a company

  SELECT name, cost_model, state, monthly_budget
    FROM campaigns
   WHERE company_id = 5
  ORDER BY monthly_budget DESC
  LIMIT 10;

This is a typical query for a multi-tenant application because it restricts the results to data from a single company. Each tenant, in this case an advertising company, will be accessing only their own data.

Any column of the :code:`campaigns` table could be its distribution column, but let's compare how this query performs for either of two options: :code:`id` and :code:`company_id`.

DIAGRAM: show id pulling from all workers, and company_id routed to one

If we distribute by the campaign id, then campaign shards will be spread across multiple workers irrespective of company. Finding the top ten monthly campaign budgets for a company requires asking all workers for their local top ten and doing a final sort and filter on the coordinator. If we distribute by :code:`company_id`, on the other hand, then Citus can detect by the presence of :code:`WHERE company_id = 5` that all relevant information will be on a single worker. Citus can route the entire query to that worker for execution and pass the results through verbatim.

The order/limit query slightly favors distribution by :code:`company_id`. However JOIN queries differ more dramatically.

.. note::

  In our normalized schema above, the ads table does not have a company_id column because it can retrieve that information through the campaigns table. If we want to distribute the ads table by company id however, we would need to denormalize the schema slightly and add that column. The query below assumes we have done this, and we'll talk more about this technique later.

::

  -- running campaigns which receive the most clicks and impressions
  -- for a single tenant

  SELECT campaigns.id, campaigns.name, campaigns.monthly_budget,
         sum(impressions_count) as total_impressions,
         sum(clicks_count) as total_clicks
  FROM ads, campaigns
  WHERE ads.company_id = campaigns.company_id
  AND campaigns.company_id = 5
  AND campaigns.state = 'running'
  GROUP BY campaigns.id, campaigns.name, campaigns.monthly_budget
  ORDER BY total_impressions, total_clicks;

DIAGRAM: show id repartitioning, and company_id routing

For this query, distributing by campaign id is quite bad. Workers must use a lot of network traffic to pull related information together for the join, in a process called *repartitioning.* Routing the query for execution in a single worker avoids the overhead, and is possible when distributing by :code:`company_id`. The placement of related information together on a worker is called *co-location.*

These queries indicate a general design pattern: distributing shards by tenant id (such as the company id) allows Citus to route queries to individual workers for efficient processing. This fits multi-tenant applications which join structured information together per-tenant.
