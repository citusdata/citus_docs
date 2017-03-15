.. _single_machine_docker:

Docker (Mac or Linux)
=====================

This section describes setting up a Citus cluster on a single machine using docker-compose.

**1. Install Docker Community Edition and Docker Compose**

*On Mac:*

* Install `Docker <https://www.docker.com/community-edition#/download>`_.
* Start Docker by clicking on the application's icon.

*On Linux:*

.. code-block:: bash

  curl -sSL https://get.docker.com/ | sh
  sudo usermod -aG docker $USER && exec sg docker newgrp `id -gn`
  sudo systemctl start docker

  sudo curl -sSL https://github.com/docker/compose/releases/download/1.11.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose

The above version of Docker Compose is sufficient for running Citus, or you can install the `latest version <https://github.com/docker/compose/releases/latest>`_.

**2. Start the Citus Cluster**

Citus uses Docker Compose to run and connect containers holding the database master node, workers, and a persistent data volume. To create a local cluster download our Docker Compose configuration file and run it

.. code-block:: bash

  curl -L https://raw.githubusercontent.com/citusdata/docker/master/docker-compose.yml > docker-compose.yml
  docker-compose -p citus up -d

The first time you start the cluster it builds its containers. Subsequent startups take a matter of seconds.

.. note::

  If you already have PostgreSQL running on your machine you may encounter this error when starting the Docker containers:

  .. code::

    Error starting userland proxy:
    Bind for 0.0.0.0:5432: unexpected error address already in use

  This is because the "master" service attempts to bind to the standard PostgreSQL port 5432. Simply adjust :code:`docker-compose.yml`. Under the :code:`master` section change the host port from 5432 to 5433 or another non-conflicting number.

  .. code-block:: diff

    - ports: ['5432:5432']
    + ports: ['5433:5432']

**3. Verify that installation has succeeded**

To verify that the installation has succeeded we check that the master node has picked up the desired worker configuration. First start the psql shell on the master node:

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

  docker-compose -p citus down
