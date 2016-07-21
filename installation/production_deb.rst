.. highlight:: bash

.. _production_deb:

Multi-node setup on Ubuntu or Debian
=======================================================

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines using deb packages.

.. _production_deb_all_nodes:

Steps to be executed on all nodes
---------------------------------

**1. Add PGDG repository**

::

  # add postgresql-9.5-citus pgdg repository
  echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list
  sudo apt-get install wget ca-certificates
  wget --quiet --no-check-certificate -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
  sudo apt-get update

**2. Install PostgreSQL + Citus and initialize a database**

::

  # install the server and initialize db
  sudo apt-get -y install postgresql-9.5-citus

  # preload citus extension
  sudo pg_conftool 9.5 main set shared_preload_libraries citus

This installs centralized configuration in `/etc/postgresql/9.5/main`, and creates a database in `/var/lib/postgresql/9.5/main`.

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo pg_conftool 9.5 main set listen_addresses '*'

::

  sudo vi /etc/postgresql/9.5/main/pg_hba.conf

::

  # Allow unrestricted access to nodes in the local network. The following ranges
  # correspond to 24, 20, and 16-bit blocks in Private IPv4 address spaces.
  host    all             all             10.0.0.0/8              trust

  # Also allow the host unrestricted access to connect to itself
  host    all             all             127.0.0.1/32            trust
  host    all             all             ::1/128                 trust

.. note::
  Your DNS settings may differ. Also these settings are too permissive for some environments. The PostgreSQL manual `explains how <http://www.postgresql.org/docs/9.5/static/auth-pg-hba-conf.html>`_ to make them more restrictive.

**4. Start database servers, create Citus extension**

::

  # start the db server
  sudo service postgresql restart
  # and make it start automatically when computer does
  sudo update-rc.d postgresql enable

You must add the Citus extension to **every database** you would like to use in a cluster. The following example adds the extension to the default database which is named `postgres`.

::

  # add the citus extension
  sudo -i -u postgres psql -c "CREATE EXTENSION citus;"

.. _production_deb_master_node:

Steps to be executed on the master node
---------------------------------------

The steps listed below must be executed **only** on the master node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the master about its workers. To add this information, we append the worker database names and server ports to the `pg_worker_list.conf` file in the data directory. For our example, we assume that there are two workers (named worker-101, worker-102). Add the workers' DNS names and server ports to the list.

::

  echo "worker-101 5432" | sudo -u postgres tee -a /var/lib/postgresql/9.5/main/pg_worker_list.conf
  echo "worker-102 5432" | sudo -u postgres tee -a /var/lib/postgresql/9.5/main/pg_worker_list.conf

Note that you can also add this information by editing the file using your favorite editor.

**2. Reload master database settings**

::

  sudo service postgresql reload

**3. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the master node has picked up the desired worker configuration. This command when run in the psql shell should output the worker nodes mentioned in the `pg_worker_list.conf` file.

::

  sudo -i -u postgres psql -c "SELECT * FROM master_get_active_worker_nodes();"

**Ready to use Citus**

At this step, you have completed the installation process and are ready to use your Citus cluster. To help you get started, we have a :ref:`tutorial<tut_hash>` which has instructions on setting up a Citus cluster with sample data in minutes.

Your new Citus database is accessible in psql through the postgres user:

::

  sudo -i -u postgres psql
