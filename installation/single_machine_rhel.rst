.. highlight:: bash

.. _single_machine_rhel:

Fedora, CentOS, or Red Hat
==========================

This section describes the steps needed to set up a single-node Citus cluster on your own Linux machine from RPM packages.

**1. Install PostgreSQL 9.6 and the Citus extension**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/rpm.sh | sudo bash

  # install Citus extension
  sudo yum install -y citus70_96

.. _post_install:

**2. Initialize the Cluster**

Citus has two kinds of components, the coordinator and the workers. The coordinator coordinates queries and maintains metadata on where in the cluster each row of data is. The workers hold your data and respond to queries.

Let's create directories for those nodes to store their data. For convenience in using PostgreSQL Unix domain socket connections we'll use the postgres user.

::

  # this user has access to sockets in /var/run/postgresql
  sudo su - postgres

  # include path to postgres binaries
  export PATH=$PATH:/usr/pgsql-9.6/bin

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
