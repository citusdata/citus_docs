.. _single_machine_docker:

Docker (Mac or Linux)
=====================

This section describes setting up Citus on a single machine using Docker.

.. note::
   **The Docker image is intended for development/testing purposes only**, and
   has not been prepared for production use. The images use default connection
   settings, which are very permissive, and not suitable for any kind of
   production setup. These should be updated before using the image for
   production use. The PostgreSQL manual `explains how
   <http://www.postgresql.org/docs/current/static/auth-pg-hba-conf.html>`_ to
   make them more restrictive.

Citus uses Docker Compose to run and connect containers holding the database coordinator node, workers, and a persistent data volume. To create a local cluster download our Docker Compose configuration file and run it

.. code-block:: bash

  docker run -d --name citus -e POSTGRES_PASSWORD=MyFirstCitus citusdata/citus:10.0.0

The first time you start the cluster it builds its containers. Subsequent startups take a matter of seconds.

.. note::

  If you already have PostgreSQL running on your machine you may encounter this error when starting the Docker containers:

  .. code::

    Error starting userland proxy:
    Bind for 0.0.0.0:5432: unexpected error address already in use

  This is because the "master" (coordinator) service attempts to bind to the standard PostgreSQL port 5432. Simply choose a different port for coordinator service with the ``MASTER_EXTERNAL_PORT`` environment variable. For example:

  .. code::

    MASTER_EXTERNAL_PORT=5433 COMPOSE_PROJECT_NAME=citus docker-compose up -d


**3. Verify that installation has succeeded**

To verify that the installation has succeeded we check that the coordinator node has picked up the desired worker configuration. First start the psql shell on the coordinator (master) node:

.. code-block:: bash

  docker exec -it citus psql -U postgres

Then run this query:

.. code-block:: postgresql

  SELECT * FROM citus_version();

You should see a row for each worker node including the node name and port.

Once you have the cluster up and running, you can visit our tutorials on :ref:`multi-tenant applications <multi_tenant_tutorial>` or :ref:`real-time analytics <real_time_analytics_tutorial>` to get started with Citus in minutes.
