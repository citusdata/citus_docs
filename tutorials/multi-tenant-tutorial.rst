.. _multi_tenant_tutorial:
.. highlight:: sql

Multi-tenant application
########################

In this tutorial, we will use a sample ad-analytics dataset to help you get started on       
using Citus as the database to power a multi-tenant application.                             

.. note::
                                                                                             
    This tutorial assumes that you already have Citus installed and running. If you haven't installed Citus yet,
    please visit ....


Data model and Schema
---------------------

We will demo building the database for an ad-analytics app which companies can use to view, change,
analyze and manage their ads and campaigns. To represent this data in the data model, we will use three tables:-
Companies, campaigns and ads.                                                                
                                                                                             
Such an application and data model have good characteristics of a typical multi-tenant system. Data from different tenants is stored in a central database system, and each tenant has an isolated view of their own data.
                                                                                             
To get started, you can connect to the co-ordinator node of the Citus cluster and create tables using standard Postgres CREATE TABLE statements.

::

    psql ......

    CREATE TABLE companies (                                                                     
        id integer NOT NULL,                                                                     
        name text NOT NULL,                                                                      
        image_url text NOT NULL,                                                                 
        created_at timestamp without time zone NOT NULL,                                         
        updated_at timestamp without time zone NOT NULL                                          
    );                                                                                           
                                                                                             
    CREATE TABLE campaigns (                                                                     
        id integer NOT NULL,                                                                     
        company_id integer NOT NULL,                                                             
        name text NOT NULL,                                                                      
        cost_model text NOT NULL,                                                                
        state text NOT NULL,                                                                     
        monthly_budget integer,                                                                  
        blacklisted_site_urls character varying[],                                               
        created_at timestamp without time zone NOT NULL,                                         
        updated_at timestamp without time zone NOT NULL                                          
    );                                                                                           
                                                                                             
    CREATE TABLE ads (                                                                           
        id integer NOT NULL,                                                                     
        company_id integer NOT NULL,                                                             
        campaign_id integer NOT NULL,                                                            
        name text NOT NULL,                                                                      
        image_url text NOT NULL,                                                                 
        target_url text NOT NULL,                                                                
        impressions_count bigint DEFAULT 0 NOT NULL,                                             
        clicks_count bigint DEFAULT 0 NOT NULL,                                                  
        created_at timestamp without time zone NOT NULL,                                         
        updated_at timestamp without time zone NOT NULL                                          
    );                                                                                           
                                                                                             
Next, you can create primary key indexes on each of the tables in order to ensure uniqueness and data consistency.
    
::
                                                                                         
    ALTER TABLE companies ADD PRIMARY KEY (id);                                                  
    ALTER TABLE campaigns ADD PRIMARY KEY (id, company_id);                                      
    ALTER TABLE ads ADD PRIMARY KEY (id, company_id);

Distributing tables and loading data
-------------------------------------

Now, the Postgres tables for distribution. We will now go ahead and      
tell Citus to shard those tables across the different nodes we have in the cluster. To do so,
you can run `create_distributed_table` and specify the table you want to shard and the key you want to shard on.
In this case, we will shard all the tables on the `company_id`.                             
                                                                                          
::
    
    SELECT create_distributed_table('companies', 'id');                                       
    SELECT create_distributed_table('campaigns', 'company_id');                               
    SELECT create_distributed_table('ads', 'company_id');                                     
                                                                                          
Sharding all tables on the company identifier allows Citus to store all data for          
a single company on a single node and provide full SQL coverage for queries for a particular company.
To understand the benefits of using this approach, you can visit our blog post here.      
                                                                                          
We could now go ahead and load data into these tables. You can download sample files for all the tables from:
a, b and c. Once you have these files, you can go ahead and load them using the standard PostgreSQL `\COPY` command.

::
                                                                                          
    \copy companies from 'companies.csv';                                                     
    \copy campaigns from 'campaigns.csv';                                                     
    \copy ads from 'ads.csv';

Running queries and modifications
---------------------------------

Now that the data is loaded, let's go ahead and run some queries.                         
                                                                                          
Lets start with a very simple count query to see how many companies we have.              
                                                                                          
::

    SELECT count(*) from companies;                                                           
                                                                                          
A more interesting query for a company to run would be to see details about its top 10 campaigns.
We could do that by running something like the below.                                     

::
                                                                                          
    SELECT name, cost_model, state, monthly_budget FROM campaigns where company_id = 5 ORDER BY monthly_budget LIMIT 10;
                                                                                          
As we sharded the data on company_id, we can also run a join query across multiple table. An example would be the
query below to see information about your running campaigns which receive the most clicks and impressions.

::
                                                                                          
    SELECT campaigns.id, campaigns.name, campaigns.monthly_budget, sum(impressions_count) as total_impressions, sum(clicks_count) as total_clicks
    FROM ads, campaigns                                                                       
    WHERE ads.company_id = campaigns.company_id                                               
    AND campaigns.company_id = 7                                                              
    AND campaigns.state = 'running'                                                           
    GROUP BY campaigns.id, campaigns.name, campaigns.monthly_budget                           
    ORDER BY total_impressions, total_clicks;                                                 
                                                                                          
Other than being able to run ad-hoc SQL for analytics, you can also run standard UPDATE and DELETE commands on your
distributed table. For eg. if you want to update your budget for a particular campaign, you can do something like:

::                                                                                          
    
    UPDATE campaigns SET monthly_budget = monthly_budget*2 WHERE id = 1 AND company_id = 5;   
                                                                                          
Because of these features, it becomes easy for ORMs and applications running on Postgres to transition to Citus.
Another example of such an operation would be the ability to run transactions which span multiple tables. Let's say you
want to delete a campaign and all its associated ads, you could do it atomically by running.

::                                                                                          
    
    BEGIN;                                                                                    
    DELETE from campaigns where id = 1 AND company_id = 5;                                    
    DELETE from ads where campaign_id = 1 AND company_id = 5;                                 
    COMMIT;                                                                                   
                                                                                          
This brings us to the end of our tutorial. If you'd like to model your own data for multi-tenancy, you can
refer to []() or contact us for any advise.   
