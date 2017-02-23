.. _single_machine_docker:

Docker
======

This section describes setting up a Citus cluster on a single machine using docker-compose.

**1. Install docker and docker-compose**

Follow the installation instructions for `Docker Engine <https://docs.docker.com/engine/installation/>`_ and `Docker Compose <https://docs.docker.com/compose/install/>`_ on your platform.

**2. Start the Citus Cluster**

Citus uses docker-compose to run and connect containers holding the database master node, workers, and a persistent data volume. To create a local cluster download our docker-compose configuration file and run it

.. code-block:: bash

  wget https://raw.githubusercontent.com/citusdata/docker/master/docker-compose.yml
  docker-compose -p citus up -d

The first time you start the cluster it builds its containers. Subsequent startups take a matter of seconds.

.. note::

  If you have PostgreSQL running on your machine you may encounter this error when starting the Docker containers:

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

.. code-block:: bash

  select * from master_get_active_worker_nodes();

You should see a row for each worker node including the node name and port.

Once you have the cluster up and running, you can visit our :ref:`tutorial <multi_tenant_tutorial>` to
get started with a sample dataset on Citus in minutes.

**4. Shut down the cluster when ready**

When you wish to stop the docker containers, use docker-compose:

.. code-block:: bash

  docker-compose -p citus down
