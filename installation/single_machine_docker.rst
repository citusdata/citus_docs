.. _single_machine_docker:

Docker (Mac or Linux)
=====================

This section describes setting up a Citus cluster on a single machine using docker-compose.

.. note::
   **The Docker image is intended for development/testing purposes only**, and
   has not been prepared for production use. The images use default connection
   settings, which are very permissive, and not suitable for any kind of
   production setup. These should be updated before using the image for
   production use. The PostgreSQL manual `explains how <http:\//www.postgresql.org/docs/current/static/auth-pg-hba-conf.html>`_ to
   make them more restrictive.

**1. Install Docker Community Edition and Docker Compose**

*On Mac:*

* Install `Docker <https://www.docker.com/community-edition#/download>`_.
* Start Docker by clicking on the application's icon.

*On Linux:*

.. code-block:: bash

  curl -sSL https://get.docker.com/ | sh
  sudo usermod -aG docker $USER && exec sg docker newgrp `id -gn`
  sudo systemctl start docker

  sudo curl -sSL https://github.com/docker/compose/releases/download/1.16.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose

The above version of Docker Compose is sufficient for running Citus, or you can install the `latest version <https://github.com/docker/compose/releases/latest>`_.

.. _post_install:

**2. Start the Citus Cluster**

Citus uses Docker Compose to run and connect containers holding the database coordinator node, workers, and a persistent data volume. To create a local cluster download our Docker Compose configuration file and run it

.. code-block:: bash

  curl -L https://raw.githubusercontent.com/citusdata/docker/master/docker-compose.yml > docker-compose.yml
  COMPOSE_PROJECT_NAME=citus docker-compose up -d

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

  docker exec -it citus_master psql -U postgres

Then run this query:

.. code-block:: postgresql

  SELECT * FROM master_get_active_worker_nodes();

You should see a row for each worker node including the node name and port.

Once you have the cluster up and running, you can visit our tutorials on :ref:`multi-tenant applications <multi_tenant_tutorial>` or :ref:`real-time analytics <real_time_analytics_tutorial>` to get started with Citus in minutes.

**4. Shut down the cluster when ready**

When you wish to stop the docker containers, use Docker Compose:

.. code-block:: bash

  COMPOSE_PROJECT_NAME=citus docker-compose down -v

.. note::

  Please note that Citus reports anonymous information about your cluster to the Citus Data company servers. To learn more about what information is collected and how to opt out of it, see :ref:`phone_home`.
