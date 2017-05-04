.. highlight:: postgresql

Multi-tenant Applications
#########################

Many companies with web applications cater not to end users, but to other businesses with customers of their own. When many clients with similar needs are expected, it makes sense to run a single instance of the application to handle all the clients.

A software-as-a-service (SaaS) provider, for example, can run one instance of its application on one instance of a database and provide web access to multiple customers. In such a scenario, each tenant's data is isolated and remains invisible to other tenants. It's efficient in two ways. First application improvements apply to all clients. Second, sharing a database between tenants uses hardware efficiently.

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

