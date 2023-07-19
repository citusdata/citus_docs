.. _microservices_tutorial:

Microservices
=============

In this tutorial, we will use Citus as the storage backend for multiple microservices, demonstrating a sample setup and basic operation of such a cluster.

.. note::

    This tutorial assumes that you already have Citus installed and running. If you don't have Citus running,
    you can setup Citus locally using one of the options from :ref:`development`.


Distributed schemas
-------------------
Distributed schemas are relocatable within a Citus cluster. The system can rebalance them as a whole unit across the available nodes, allowing to effeciently share resources without manual allocation.

By design, microservices own their storage layer, we won't make any assumptions on the type of tables and data that they will create and store. We will however provide a schema for every service and assume that they will use a distinct `ROLE`
to connect to the database. When a user connects, their role name is put at the beginning of the `search_path`, so if the role matches with the schema name you won't need any application changes to set the correct `search_path`.

We will use three services in our example:

* user service
* time service
* ping service

To start, you can first connect to the Citus coordinator using psql.

**If you are using native Postgres**, as installed in our :ref:`development` guide, the coordinator node will be running on port 9700.

.. code-block:: bash

   psql -p 9700

**If you are using Docker**, you can connect by running psql with the docker exec command:

.. code-block:: bash

    docker exec -it citus psql -U postgres

You can now create the database roles for every service:

.. code-block:: sql

    CREATE USER user_service;
    CREATE USER time_service;
    CREATE USER ping_service;

There are two ways in which a schema can be distributed in Citus:

Manually by calling `citus_schema_distribute(schema_name)` function:

.. code-block:: sql

    CREATE SCHEMA AUTHORIZATION user_service;
    CREATE SCHEMA AUTHORIZATION time_service;
    CREATE SCHEMA AUTHORIZATION ping_service;

    SELECT citus_schema_distribute('user_service');
    SELECT citus_schema_distribute('time_service');
    SELECT citus_schema_distribute('ping_service');

This method also allows you to convert existing regular schemas into distributed schemas.

.. note::

    You can only distribute schemas that do not contain distributed and reference tables.

Alternative approach is to enable `citus.enable_schema_based_sharding` configuration variable:

.. code-block:: sql

    SET citus.enable_schema_based_sharding TO ON;

    CREATE SCHEMA AUTHORIZATION user_service;
    CREATE SCHEMA AUTHORIZATION time_service;
    CREATE SCHEMA AUTHORIZATION ping_service;

The variable can be changed for the current session or permanently in `postgresql.conf`. With the parameter set to `ON` all created schemas will be distributed by default.

You can list the currently distributed schemas:

.. code-block:: sql

    select * from citus_schemas;

.. code-block:: text

     schema_name  | colocation_id | schema_size | schema_owner
    --------------+---------------+-------------+--------------
     user_service |             5 | 0 bytes     | user_service
     time_service |             6 | 0 bytes     | time_service
     ping_service |             7 | 0 bytes     | ping_service
    (3 rows)


Creating tables
---------------

You now need to connect to the Citus coordinator for every microservice. You can use the `\\c` command to swap the user within an existing `psql` instance.


.. code-block:: psql

    \c citus user_service

.. code-block:: sql

    CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) NOT NULL
    );

.. code-block:: psql

    \c citus time_service

.. code-block:: sql

    CREATE TABLE query_details (
        id SERIAL PRIMARY KEY,
        ip_address INET NOT NULL,
        query_time TIMESTAMP NOT NULL
    );

.. code-block:: psql

    \c citus ping_service

.. code-block:: sql

    CREATE TABLE ping_results (
        id SERIAL PRIMARY KEY,
        host VARCHAR(255) NOT NULL,
        result TEXT NOT NULL
    );


Configure services
------------------

For the purpose of this tutorial we will use a very simple set of services. You can obtain them by cloning this public repository:

::

    git clone https://github.com/citusdata/citus-example-microservices.git

The repository contains the ping, time and user service. All of them have an `app.py` that we will run.

::

    $ tree
    .
    ├── LICENSE
    ├── README.md
    ├── ping
    │   ├── app.py
    │   ├── ping.sql
    │   └── requirements.txt
    ├── time
    │   ├── app.py
    │   ├── requirements.txt
    │   └── time.sql
    └── user
        ├── app.py
        ├── requirements.txt
        └── user.sql

Before you run the services however, edit `user/app.py`, `ping/app.py` and `time/app.py` files providing the `connection configuration <https://www.psycopg.org/docs/module.html#psycopg2.connect>`_ for your Citus cluster:

.. code-block:: python

    # Database configuration
    db_config = {
        'host': 'localhost',
        'database': 'citus',
        'user': 'ping_service',
        'port': 9700
    }


After making the changes, save all modified files and move on to the next step of running the services.

Running the services
--------------------

Change into every app directory and run them in their own python env.


.. code-block:: shell

    cd use
    pipenv install
    pipenv shell
    python app.py

Repeat the above for `time` and `ping` service, after which you can use the API.

Create some users:

.. code-block:: shell
    
    curl -X POST -H "Content-Type: application/json" -d '[
      {"name": "John Doe", "email": "john@example.com"},
      {"name": "Jane Smith", "email": "jane@example.com"},
      {"name": "Mike Johnson", "email": "mike@example.com"},
      {"name": "Emily Davis", "email": "emily@example.com"},
      {"name": "David Wilson", "email": "david@example.com"},
      {"name": "Sarah Thompson", "email": "sarah@example.com"},
      {"name": "Alex Miller", "email": "alex@example.com"},
      {"name": "Olivia Anderson", "email": "olivia@example.com"},
      {"name": "Daniel Martin", "email": "daniel@example.com"},
      {"name": "Sophia White", "email": "sophia@example.com"}
    ]' http://localhost:5000/users

List the created users:

.. code-block:: shell
    
    curl http://localhost:5000/users


Get current time:

.. code-block:: shell
    
    curl http://localhost:5001/current_time


Run the ping against example.com:

.. code-block:: shell

    curl -X POST -H "Content-Type: application/json" -d '{"host": "example.com"}' http://localhost:5002/ping


Exploring the database
----------------------

Now that we called some API functions, data has been stored and we can check if `citus_schemas` reflects what we expect:

.. code-block:: sql

    select * from citus_schemas;

.. code-block:: text

     schema_name  | colocation_id | schema_size | schema_owner
    --------------+---------------+-------------+--------------
     user_service |             1 | 112 kB      | user_service
     time_service |             2 | 32 kB       | time_service
     ping_service |             3 | 32 kB       | ping_service
    (3 rows)

When we created the schemas, we didn't tell Citus on which machines to create the schemas. It has done this for us automatically. We can see where each schema resides with the following query:

.. code-block:: sql

      select nodename,nodeport, table_name, pg_size_pretty(sum(shard_size))
        from citus_shards
    group by nodename,nodeport, table_name;

.. code-block:: text

     nodename  | nodeport |         table_name         | pg_size_pretty
    -----------+----------+----------------------------+----------------
     localhost |     9701 | time_service.query_details | 32 kB
     localhost |     9702 | user_service.users         | 112 kB
     localhost |     9702 | ping_service.ping_results  | 32 kB

We can see that the time service landed on node `localhost:9701` while the user and ping service share space on the second worker `localhost:9702`.
This is a toy example, and the data sizes here are ignorable, but let's assume that we are annoyed by the uneven storage space utilization between the nodes. It would make more sense to have the two smaller time and ping services reside on one machine while the large user service resides alone.

We can do this easily, by asking Citus to rebalance the cluster by disk size:

.. code-block:: sql

    select citus_rebalance_start();

.. code-block:: text

    NOTICE:  Scheduled 1 moves as job 1
    DETAIL:  Rebalance scheduled as background job
    HINT:  To monitor progress, run: SELECT * FROM citus_rebalance_status();
     citus_rebalance_start
    -----------------------
                         1
    (1 row)

When done, we can check how our new layout looks:

.. code-block:: sql

      select nodename,nodeport, table_name, pg_size_pretty(sum(shard_size))
        from citus_shards
    group by nodename,nodeport, table_name;

.. code-block:: text

     nodename  | nodeport |         table_name         | pg_size_pretty
    -----------+----------+----------------------------+----------------
     localhost |     9701 | time_service.query_details | 32 kB
     localhost |     9701 | ping_service.ping_results  | 32 kB
     localhost |     9702 | user_service.users         | 112 kB
    (3 rows)

According to our expectations, the schemas have been moved and we have a more balanced cluster. This operation has been transparent for the applications. We don't even need to restart them, they will continue serving queries.


With this, we come to the end of our tutorial on using Citus as storage for microservices.
