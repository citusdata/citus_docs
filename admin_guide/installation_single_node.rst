.. _development:

Single-Machine Dev Cluster
==========================

If you are a developer looking to try Citus out on your machine, the guides below will help you get started quickly.

.. _single_machine_docker:

Docker (Mac or Linux)
---------------------

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

.. _single_machine_deb:

Ubuntu or Debian
----------------

This section describes the steps needed to set up a single-node Citus cluster on your own Linux machine from deb packages.

**1. Install PostgreSQL 10 and the Citus extension**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/deb.sh | sudo bash

  # install the server and initialize db
  sudo apt-get -y install postgresql-10-citus-7.3


.. _post_install:

**2. Initialize the Cluster**

Citus has two kinds of components, the coordinator and the workers. The coordinator coordinates queries and maintains metadata on where in the cluster each row of data is. The workers hold your data and respond to queries.

Let's create directories for those nodes to store their data. For convenience in using PostgreSQL Unix domain socket connections we'll use the postgres user.

::

  # this user has access to sockets in /var/run/postgresql
  sudo su - postgres

  # include path to postgres binaries
  export PATH=$PATH:/usr/lib/postgresql/10/bin

  cd ~
  mkdir -p citus/coordinator citus/worker1 citus/worker2

  # create three normal postgres instances
  initdb -D citus/coordinator
  initdb -D citus/worker1
  initdb -D citus/worker2

Citus is a Postgres extension, to tell Postgres to use this extension you'll need to add it to a configuration variable called ``shared_preload_libraries``:

::

  echo "shared_preload_libraries = 'citus'" >> citus/coordinator/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker1/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker2/postgresql.conf

**3. Start the coordinator and workers**

We will start the PostgreSQL instances on ports 9700 (for the coordinator) and 9701, 9702 (for the workers). We assume those ports are available on your machine. Feel free to use different ports if they are in use.

Let's start the databases::

  pg_ctl -D citus/coordinator -o "-p 9700" -l coordinator_logfile start
  pg_ctl -D citus/worker1 -o "-p 9701" -l worker1_logfile start
  pg_ctl -D citus/worker2 -o "-p 9702" -l worker2_logfile start


Above you added Citus to ``shared_preload_libraries``. That lets it hook into some deep parts of Postgres, swapping out the query planner and executor.  Here, we load the user-facing side of Citus (such as the functions you'll soon call):

::

  psql -p 9700 -c "CREATE EXTENSION citus;"
  psql -p 9701 -c "CREATE EXTENSION citus;"
  psql -p 9702 -c "CREATE EXTENSION citus;"

Finally, the coordinator needs to know where it can find the workers. To tell it you can run:

::

  psql -p 9700 -c "SELECT * from master_add_node('localhost', 9701);"
  psql -p 9700 -c "SELECT * from master_add_node('localhost', 9702);"

**4. Verify that installation has succeeded**

To verify that the installation has succeeded we check that the coordinator node has picked up the desired worker configuration. First start the psql shell on the coordinator node:

::

  psql -p 9700 -c "select * from master_get_active_worker_nodes();"

You should see a row for each worker node including the node name and port.

At this step, you have completed the installation process and are ready to use your Citus cluster. To help you get started, we have a :ref:`tutorial<multi_tenant_tutorial>` which has instructions on setting up a Citus cluster with sample data in minutes.

.. note::

  Please note that Citus reports anonymous information about your cluster to the Citus Data company servers. To learn more about what information is collected and how to opt out of it, see :ref:`phone_home`.

.. _single_machine_rhel:

Fedora, CentOS, or Red Hat
--------------------------

This section describes the steps needed to set up a single-node Citus cluster on your own Linux machine from RPM packages.

**1. Install PostgreSQL 10 and the Citus extension**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/rpm.sh | sudo bash

  # install Citus extension
  sudo yum install -y citus73_10

.. _post_install:

**2. Initialize the Cluster**

Citus has two kinds of components, the coordinator and the workers. The coordinator coordinates queries and maintains metadata on where in the cluster each row of data is. The workers hold your data and respond to queries.

Let's create directories for those nodes to store their data. For convenience in using PostgreSQL Unix domain socket connections we'll use the postgres user.

::

  # this user has access to sockets in /var/run/postgresql
  sudo su - postgres

  # include path to postgres binaries
  export PATH=$PATH:/usr/pgsql-10/bin

  cd ~
  mkdir -p citus/coordinator citus/worker1 citus/worker2

  # create three normal postgres instances
  initdb -D citus/coordinator
  initdb -D citus/worker1
  initdb -D citus/worker2

Citus is a Postgres extension, to tell Postgres to use this extension you'll need to add it to a configuration variable called ``shared_preload_libraries``:

::

  echo "shared_preload_libraries = 'citus'" >> citus/coordinator/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker1/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker2/postgresql.conf

**3. Start the coordinator and workers**

We will start the PostgreSQL instances on ports 9700 (for the coordinator) and 9701, 9702 (for the workers). We assume those ports are available on your machine. Feel free to use different ports if they are in use.

Let's start the databases::

  pg_ctl -D citus/coordinator -o "-p 9700" -l coordinator_logfile start
  pg_ctl -D citus/worker1 -o "-p 9701" -l worker1_logfile start
  pg_ctl -D citus/worker2 -o "-p 9702" -l worker2_logfile start


Above you added Citus to ``shared_preload_libraries``. That lets it hook into some deep parts of Postgres, swapping out the query planner and executor.  Here, we load the user-facing side of Citus (such as the functions you'll soon call):

::

  psql -p 9700 -c "CREATE EXTENSION citus;"
  psql -p 9701 -c "CREATE EXTENSION citus;"
  psql -p 9702 -c "CREATE EXTENSION citus;"

Finally, the coordinator needs to know where it can find the workers. To tell it you can run:

::

  psql -p 9700 -c "SELECT * from master_add_node('localhost', 9701);"
  psql -p 9700 -c "SELECT * from master_add_node('localhost', 9702);"

**4. Verify that installation has succeeded**

To verify that the installation has succeeded we check that the coordinator node has picked up the desired worker configuration. First start the psql shell on the coordinator node:

::

  psql -p 9700 -c "select * from master_get_active_worker_nodes();"

You should see a row for each worker node including the node name and port.

At this step, you have completed the installation process and are ready to use your Citus cluster. To help you get started, we have a :ref:`tutorial<multi_tenant_tutorial>` which has instructions on setting up a Citus cluster with sample data in minutes.

.. note::

  Please note that Citus reports anonymous information about your cluster to the Citus Data company servers. To learn more about what information is collected and how to opt out of it, see :ref:`phone_home`.
