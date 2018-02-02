Tutorials
#########

.. _multi_tenant_tutorial:

Multi-tenant Applications
=========================

In this tutorial, we will use a sample ad analytics dataset to demonstrate how you can       
use Citus to power your multi-tenant application.                             

.. note::
                                                                                             
    This tutorial assumes that you already have Citus installed and running. If you don't have Citus running,
    you can:
    
    * Provision a cluster using `Citus Cloud <https://console.citusdata.com/users/sign_up>`_, or
    
    * Setup Citus locally using :ref:`single_machine_docker`.


Data model and sample data 
---------------------------

We will demo building the database for an ad-analytics app which companies can use to view, change,
analyze and manage their ads and campaigns (see an `example app <http://citus-example-ad-analytics.herokuapp.com/>`_).
Such an application has good characteristics of a typical multi-tenant system. Data from different tenants is stored in a central database, and each tenant has an isolated view of their own data.

We will use three Postgres tables to represent this data. To get started, you will need to download sample data for these tables:

::

    curl https://examples.citusdata.com/tutorial/companies.csv > companies.csv
    curl https://examples.citusdata.com/tutorial/campaigns.csv > campaigns.csv
    curl https://examples.citusdata.com/tutorial/ads.csv > ads.csv

**If you are using Docker**, you should use the :code:`docker cp` command to copy the files into the Docker container. 

::

    docker cp companies.csv citus_master:.
    docker cp campaigns.csv citus_master:.
    docker cp ads.csv citus_master:.
            
Creating tables 
---------------
                                                                                             
To start, you can first connect to the Citus co-ordinator using psql.

**If you are using Citus Cloud**, you can connect by specifying the connection string (URL in the formation details):
    
::
    
    psql connection-string

Please note that certain shells may require you to quote the connection string when connecting to Citus Cloud. For example, :code:`psql "connection-string"`.

**If you are using Docker**, you can connect by running psql with the docker exec command:

::
    
    docker exec -it citus_master psql -U postgres

Then, you can create the tables by using standard PostgreSQL :code:`CREATE TABLE` commands.

::

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
    
::
                                                                                         
    ALTER TABLE companies ADD PRIMARY KEY (id);                                                  
    ALTER TABLE campaigns ADD PRIMARY KEY (id, company_id);                                      
    ALTER TABLE ads ADD PRIMARY KEY (id, company_id);


Distributing tables and loading data
------------------------------------

We will now go ahead and tell Citus to distribute these tables across the different nodes we have in the cluster. To do so,
you can run :code:`create_distributed_table` and specify the table you want to shard and the column you want to shard on.
In this case, we will shard all the tables on the :code:`company_id`.                             
                                                                                          
::
    
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

::

    INSERT INTO companies VALUES (5000, 'New Company', 'https://randomurl/image.png', now(), now());

If you want to double the budget for all the campaigns of a company, you can run an UPDATE command:

::                                                                                          
    
    UPDATE campaigns
    SET monthly_budget = monthly_budget*2
    WHERE company_id = 5;   
                                                                                          
Another example of such an operation would be to run transactions which span multiple tables. Let's
say you want to delete a campaign and all its associated ads, you could do it atomically by running.

::                                                                                          
    
    BEGIN;                                                                                    
    DELETE from campaigns where id = 46 AND company_id = 5;                                    
    DELETE from ads where campaign_id = 46 AND company_id = 5;                                 
    COMMIT;                                                                                   
                                                                                          
Other than transactional operations, you can also run analytics queries on this data using standard SQL.
One interesting query for a company to run would be to see details about its campaigns with maximum budget.

::
                                                                                          
    SELECT name, cost_model, state, monthly_budget
    FROM campaigns
    WHERE company_id = 5
    ORDER BY monthly_budget DESC
    LIMIT 10;
                                                                                          
We can also run a join query across multiple tables to see information about running campaigns which receive the most clicks and impressions.

::
                                                                                          
    SELECT campaigns.id, campaigns.name, campaigns.monthly_budget,
           sum(impressions_count) as total_impressions, sum(clicks_count) as total_clicks
    FROM ads, campaigns                                                                       
    WHERE ads.company_id = campaigns.company_id                                               
    AND campaigns.company_id = 5                                                              
    AND campaigns.state = 'running'                                                           
    GROUP BY campaigns.id, campaigns.name, campaigns.monthly_budget                           
    ORDER BY total_impressions, total_clicks;                                                 
                                                                                          
With this, we come to the end of our tutorial on using Citus to power a simple multi-tenant application. As a next step, you can look at the :ref:`distributing_by_tenant_id` section to see how you can model your own data for multi-tenancy.

.. _real_time_analytics_tutorial:

Real-time Analytics
===================

In this tutorial, we will demonstrate how you can use Citus to ingest events data and run analytical queries on that data in human real-time. For that, we will use a sample Github events dataset.

.. note::
                                                                                             
    This tutorial assumes that you already have Citus installed and running. If you don't have Citus running,
    you can:
    
    * Provision a cluster using `Citus Cloud <https://console.citusdata.com/users/sign_up>`_, or
    
    * Setup Citus locally using :ref:`single_machine_docker`.


Data model and sample data 
---------------------------

We will demo building the database for a real-time analytics application. This application will insert large volumes of events data and  enable analytical queries on that data with sub-second latencies. In our example, we're going to work with the Github events dataset. This dataset includes all public events on Github, such as commits, forks, new issues, and comments on these issues.

We will use two Postgres tables to represent this data. To get started, you will need to download sample data for these tables:

::

    curl https://examples.citusdata.com/tutorial/users.csv > users.csv
    curl https://examples.citusdata.com/tutorial/events.csv > events.csv

**If you are using Docker**, you should use the :code:`docker cp` command to copy the files into the Docker container. 

::

    docker cp users.csv citus_master:.
    docker cp events.csv citus_master:.
            
Creating tables 
---------------
                                                                                             
To start, you can first connect to the Citus coordinator using psql.

**If you are using Citus Cloud**, you can connect by specifying the connection string (URL in the formation details):
    
::
    
    psql connection-string

Please note that certain shells may require you to quote the connection string when connecting to Citus Cloud. For example, :code:`psql "connection-string"`.

**If you are using Docker**, you can connect by running psql with the docker exec command:

::
    
    docker exec -it citus_master psql -U postgres

Then, you can create the tables by using standard PostgreSQL :code:`CREATE TABLE` commands.

::

    CREATE TABLE github_events                                                                   
    (                                                                                            
        event_id bigint,                                                                         
        event_type text,                                                                         
        event_public boolean,                                                                    
        repo_id bigint,                                                                          
        payload jsonb,                                                                           
        repo jsonb,                                                                              
        user_id bigint,                                                                          
        org jsonb,                                                                               
        created_at timestamp                                                                     
    );                                                                                           

    CREATE TABLE github_users                                                                    
    (                                                                                            
        user_id bigint,                                                                          
        url text,                                                                                
        login text,                                                                              
        avatar_url text,                                                                         
        gravatar_id text,                                                                        
        display_login text                                                                       
    );

Next, you can create indexes on events data just like you would do in PostgreSQL. In this example, we're also going to create a :code:`GIN` index to make querying on :code:`jsonb` fields faster.
    
::
                                                                                         
    CREATE INDEX event_type_index ON github_events (event_type);                                                  
    CREATE INDEX payload_index ON github_events USING GIN (payload jsonb_path_ops);

Distributing tables and loading data
------------------------------------

We will now go ahead and tell Citus to distribute these tables across the nodes in the cluster. To do so,
you can run :code:`create_distributed_table` and specify the table you want to shard and the column you want to shard on.
In this case, we will shard all the tables on :code:`user_id`.                             
                                                                                          
::
    
    SELECT create_distributed_table('github_users', 'user_id');                                       
    SELECT create_distributed_table('github_events', 'user_id');                               
                                                                                          
Sharding all tables on the user identifier allows Citus to :ref:`colocate <colocation>` these tables together,
and allows for efficient joins and distributed roll-ups. You can learn more about the benefits of this approach `here <https://www.citusdata.com/blog/2016/11/29/event-aggregation-at-scale-with-postgresql/>`_.
                                                                                          
Then, you can go ahead and load the data we downloaded into the tables using the standard PostgreSQL :code:`\COPY` command.
Please make sure that you specify the correct file path if you downloaded the file to a different location.

.. code-block:: psql

    \copy github_users from 'users.csv' with csv
    \copy github_events from 'events.csv' with csv


Running queries
----------------

Now that we have loaded data into the tables, let's go ahead and run some queries. First, let's check how many users we have in our distributed database.

::
                                                                                          
    SELECT count(*) FROM github_users;
    
Now, let's analyze Github push events in our data. We will first compute the number of commits per minute by using the number of distinct commits in each push event.

::
                                                                                          
    SELECT date_trunc('minute', created_at) AS minute,
           sum((payload->>'distinct_size')::int) AS num_commits
    FROM github_events
    WHERE event_type = 'PushEvent'
    GROUP BY minute
    ORDER BY minute;                                                                                          

We also have a users table. We can also easily join the users with events, and find the top ten users who created the most repositories. 

::
                                                                                          
    SELECT login, count(*)
    FROM github_events ge
    JOIN github_users gu
    ON ge.user_id = gu.user_id
    WHERE event_type = 'CreateEvent' AND payload @> '{"ref_type": "repository"}'
    GROUP BY login
    ORDER BY count(*) DESC LIMIT 10;                                                                                          

Citus also supports standard :code:`INSERT`, :code:`UPDATE`, and :code:`DELETE` commands for ingesting and modifying data. For example, you can update a user's display login by running the following command:

::
                                                                                          
    UPDATE github_users SET display_login = 'no1youknow' WHERE user_id = 24305673;

With this, we come to the end of our tutorial. As a next step, you can look at the :ref:`distributing_by_entity_id` section to see how you can model your own data and power real-time analytical applications.
