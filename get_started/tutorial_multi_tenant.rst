.. _multi_tenant_tutorial:

Multi-tenant Applications
=========================

In this tutorial, we will use a sample ad analytics dataset to demonstrate how you can
use Citus to power your multi-tenant application.

.. note::

    This tutorial assumes that you already have Citus installed and running. If you don't have Citus running,
    you can setup Citus locally using one of the options from :ref:`development`.


Data model and sample data
---------------------------

We will demo building the database for an ad-analytics app which companies can use to view, change,
analyze and manage their ads and campaigns (see an `example app <http://citus-example-ad-analytics.herokuapp.com/>`_).
Such an application has good characteristics of a typical multi-tenant system. Data from different tenants is stored in a central database, and each tenant has an isolated view of their own data.

We will use three Postgres tables to represent this data. To get started, you will need to download sample data for these tables:

.. code-block:: bash

    curl https://examples.citusdata.com/tutorial/companies.csv > companies.csv
    curl https://examples.citusdata.com/tutorial/campaigns.csv > campaigns.csv
    curl https://examples.citusdata.com/tutorial/ads.csv > ads.csv

**If you are using Docker**, you should use the :code:`docker cp` command to copy the files into the Docker container.

.. code-block:: bash

    docker cp companies.csv citus_master:.
    docker cp campaigns.csv citus_master:.
    docker cp ads.csv citus_master:.

Creating tables
---------------

To start, you can first connect to the Citus coordinator using psql.

**If you are using Docker**, you can connect by running psql with the docker exec command:

::

    docker exec -it citus_master psql -U postgres

Then, you can create the tables by using standard PostgreSQL :code:`CREATE TABLE` commands.

.. code-block:: sql

    CREATE TABLE companies (
        id bigint NOT NULL,
        name text NOT NULL,
        image_url text,
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
    );

    CREATE TABLE campaigns (
        id bigint NOT NULL,
        company_id bigint NOT NULL,
        name text NOT NULL,
        cost_model text NOT NULL,
        state text NOT NULL,
        monthly_budget bigint,
        blacklisted_site_urls text[],
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
    );

    CREATE TABLE ads (
        id bigint NOT NULL,
        company_id bigint NOT NULL,
        campaign_id bigint NOT NULL,
        name text NOT NULL,
        image_url text,
        target_url text,
        impressions_count bigint DEFAULT 0,
        clicks_count bigint DEFAULT 0,
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
    );

Next, you can create primary key indexes on each of the tables just like you would do in PostgreSQL

.. code-block:: sql

    ALTER TABLE companies ADD PRIMARY KEY (id);
    ALTER TABLE campaigns ADD PRIMARY KEY (id, company_id);
    ALTER TABLE ads ADD PRIMARY KEY (id, company_id);


Distributing tables and loading data
------------------------------------

We will now go ahead and tell Citus to distribute these tables across the different nodes we have in the cluster. To do so,
you can run :code:`create_distributed_table` and specify the table you want to shard and the column you want to shard on.
In this case, we will shard all the tables on the :code:`company_id`.

.. code-block:: sql

    SELECT create_distributed_table('companies', 'id');
    SELECT create_distributed_table('campaigns', 'company_id');
    SELECT create_distributed_table('ads', 'company_id');

Sharding all tables on the company identifier allows Citus to :ref:`colocate <colocation>` the tables together
and allow for features like primary keys, foreign keys and complex joins across your cluster.
You can learn more about the benefits of this approach `here <https://www.citusdata.com/blog/2016/10/03/designing-your-saas-database-for-high-scalability/>`_.

Then, you can go ahead and load the data we downloaded into the tables using the standard PostgreSQL :code:`\COPY` command.
Please make sure that you specify the correct file path if you downloaded the file to some other location.

.. code-block:: psql

    \copy companies from 'companies.csv' with csv
    \copy campaigns from 'campaigns.csv' with csv
    \copy ads from 'ads.csv' with csv


Running queries
----------------

Now that we have loaded data into the tables, let's go ahead and run some queries. Citus supports standard
:code:`INSERT`, :code:`UPDATE` and :code:`DELETE` commands for inserting and modifying rows in a distributed table which is the
typical way of interaction for a user-facing application.

For example, you can insert a new company by running:

.. code-block:: sql

    INSERT INTO companies VALUES (5000, 'New Company', 'https://randomurl/image.png', now(), now());

If you want to double the budget for all the campaigns of a company, you can run an UPDATE command:

.. code-block:: sql

    UPDATE campaigns
    SET monthly_budget = monthly_budget*2
    WHERE company_id = 5;

Another example of such an operation would be to run transactions which span multiple tables. Let's
say you want to delete a campaign and all its associated ads, you could do it atomically by running.

.. code-block:: sql

    BEGIN;
    DELETE from campaigns where id = 46 AND company_id = 5;
    DELETE from ads where campaign_id = 46 AND company_id = 5;
    COMMIT;

Other than transactional operations, you can also run analytics queries on this data using standard SQL.
One interesting query for a company to run would be to see details about its campaigns with maximum budget.

.. code-block:: sql

    SELECT name, cost_model, state, monthly_budget
    FROM campaigns
    WHERE company_id = 5
    ORDER BY monthly_budget DESC
    LIMIT 10;

We can also run a join query across multiple tables to see information about running campaigns which receive the most clicks and impressions.

.. code-block:: sql

    SELECT campaigns.id, campaigns.name, campaigns.monthly_budget,
           sum(impressions_count) as total_impressions, sum(clicks_count) as total_clicks
    FROM ads, campaigns
    WHERE ads.company_id = campaigns.company_id
    AND campaigns.company_id = 5
    AND campaigns.state = 'running'
    GROUP BY campaigns.id, campaigns.name, campaigns.monthly_budget
    ORDER BY total_impressions, total_clicks;

With this, we come to the end of our tutorial on using Citus to power a simple multi-tenant application. As a next step, you can look at the :ref:`distributing_by_tenant_id` section to see how you can model your own data for multi-tenancy.
