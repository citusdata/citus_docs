.. _real_time_analytics_tutorial:
.. highlight:: sql

Real-time Analytics
###################

In this tutorial, we will demonstrate how you can use Citus to ingest events data and run analytical queries on that data in human real-time. For that, we will use a sample Github events dataset.

.. note::
                                                                                             
    This tutorial assumes that you already have Citus installed and running. If you don't have Citus running,
    you can:
    
    * Provision a cluster using `Citus Cloud <https://console.citusdata.com/users/sign_up>`_, or
    
    * Setup Citus locally using :ref:`single_machine_docker`.


Data model and sample data 
---------------------------

We will demo building the database for a real-time analytics application. This application will insert large volumes of events data and  enable analytical queries on that data with sub-second latencies. In our example, we're going to work with the Github events dataset. This dataset includes all public events on Github, such as commits, forks, pull requests, new issues, and comments on these issues.

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

::
                                                                                          
    \copy github_users from 'users.csv' with csv;                                                     
    \copy github_events from 'events.csv' with csv;                                                     


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

Citus also supports standard `INSERT`, `UPDATE`, and `DELETE` commands for ingesting and modifying data. For example, you can update a user's display login by running the following command:

::
                                                                                          
    UPDATE github_users SET display_login = 'no1youknow' WHERE user_id = 24305673;

With this, we come to the end of our tutorial. As a next step, you can look at the :ref:`distributing_by_entity_id` section to see how you can model your own data and power real-time analytical applications.
