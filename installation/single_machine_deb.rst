.. highlight:: bash

.. _single_machine_deb:

Ubuntu or Debian
================

This section describes the steps needed to set up a single-node Citus cluster on your own Linux machine from deb packages.

**1. Install PostgreSQL 9.5 and the Citus extension**

::

  # add postgresql-9.5-citus pgdg repository
  echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list
  sudo apt-get install wget ca-certificates
  wget --quiet --no-check-certificate -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
  sudo apt-get update

  # install the server and initialize db
  sudo apt-get -y install postgresql-9.5-citus


**2. Initialize the Cluster**

Citus has two kinds of components, the master and the workers. The master coordinates queries and maintains metadata on where in the cluster each row of data is. The workers hold your data and respond to queries.

Let's create directories for those nodes to store their data. For convenience we suggest making subdirectories in your home folder, but feel free to choose another path.

::

  # include path to postgres binaries
  export PATH=$PATH:/usr/lib/postgresql/9.5/bin

  cd ~
  mkdir -p citus/master citus/worker1 citus/worker2

  # create three normal postgres instances
  initdb -D citus/master
  initdb -D citus/worker1
  initdb -D citus/worker2

The master needs to know where it can find the workers. To tell it you can run:

::

  echo "localhost 9701" >> citus/master/pg_worker_list.conf
  echo "localhost 9702" >> citus/master/pg_worker_list.conf

We will configure the PostgreSQL instances to use ports 9700 (for the master) and 9701, 9702 (for the workers). We assume those ports are available on your machine. Feel free to use different ports if they are in use.

Citus is a Postgres extension, to tell Postgres to use this extension you'll need to add it to a configuration variable called ``shared_preload_libraries``:

::

  echo "shared_preload_libraries = 'citus'" >> citus/master/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker1/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> citus/worker2/postgresql.conf

In order to run PostgreSQL servers under your user you will need to make the lock file accessible:

::

  sudo chmod a+w /var/run/postgresql

**3. Start the master and workers**

Let's start the databases::

  pg_ctl -D citus/master -o "-p 9700" -l master_logfile start
  pg_ctl -D citus/worker1 -o "-p 9701" -l worker1_logfile start
  pg_ctl -D citus/worker2 -o "-p 9702" -l worker2_logfile start

And initialize them::

  createdb -p 9700 $(whoami)
  createdb -p 9701 $(whoami)
  createdb -p 9702 $(whoami)

Above you added Citus to ``shared_preload_libraries``. That lets it hook into some deep parts of Postgres, swapping out the query planner and executor.  Here, we load the user-facing side of Citus (such as the functions you'll soon call):

::

  psql -p 9700 -c "CREATE EXTENSION citus;"
  psql -p 9701 -c "CREATE EXTENSION citus;"
  psql -p 9702 -c "CREATE EXTENSION citus;"

**4. Verify that installation has succeeded**

To verify that the installation has succeeded we check that the master node has picked up the desired worker configuration. First start the psql shell on the master node:

::

  psql -p 9700 -c "select * from master_get_active_worker_nodes();"

You should see a row for each worker node including the node name and port.
