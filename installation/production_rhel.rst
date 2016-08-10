.. highlight:: bash

.. _production_rhel:

Multi-node setup on Fedora, CentOS, or Red Hat
=======================================================

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines from RPM packages.

.. _production_rhel_all_nodes:

Steps to be executed on all nodes
---------------------------------

**1. Add repository**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/rpm.sh | sudo bash


**2. Install PostgreSQL + Citus and initialize a database**

::

  # install PostgreSQL with Citus extension
  sudo yum install -y citus_95
  # initialize system database (using RHEL 6 vs 7 method as necessary)
  sudo service postgresql-9.5 initdb || sudo /usr/pgsql-9.5/bin/postgresql95-setup initdb
  # preload citus extension
  echo "shared_preload_libraries = 'citus'" | sudo tee -a /var/lib/pgsql/9.5/data/postgresql.conf

PostgreSQL adds version-specific binaries in `/usr/pgsql-9.5/bin`, but you'll usually just need psql, whose latest version is added to your path, and managing the server itself can be done with the *service* command.

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo vi /var/lib/pgsql/9.5/data/postgresql.conf

::

  # Uncomment listen_addresses for the changes to take effect
  listen_addresses = '*'

::

  sudo vi /var/lib/pgsql/9.5/data/pg_hba.conf

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
  sudo service postgresql-9.5 restart
  # and make it start automatically when computer does
  sudo chkconfig postgresql-9.5 on

You must add the Citus extension to **every database** you would like to use in a cluster. The following example adds the extension to the default database which is named `postgres`.

::

  sudo -i -u postgres psql -c "CREATE EXTENSION citus;"

.. _production_rhel_master_node:

Steps to be executed on the master node
---------------------------------------

The steps listed below must be executed **only** on the master node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the master about its workers. To add this information, we append the worker database names and server ports to the `pg_worker_list.conf` file in the data directory. For our example, we assume that there are two workers (named worker-101, worker-102). Add the workers' DNS names and server ports to the list.

::

  echo "worker-101 5432" | sudo -u postgres tee -a /var/lib/pgsql/9.5/data/pg_worker_list.conf
  echo "worker-102 5432" | sudo -u postgres tee -a /var/lib/pgsql/9.5/data/pg_worker_list.conf

Note that you can also add this information by editing the file using your favorite editor.

**2. Reload master database settings**

::

  sudo service postgresql-9.5 reload

**3. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the master node has picked up the desired worker configuration. This command when run in the psql shell should output the worker nodes mentioned in the `pg_worker_list.conf` file.

::

  sudo -i -u postgres psql -c "SELECT * FROM master_get_active_worker_nodes();"

**Ready to use Citus**

At this step, you have completed the installation process and are ready to use your Citus cluster. To help you get started, we have a :ref:`tutorial<tut_hash>` which has instructions on setting up a Citus cluster with sample data in minutes.

Your new Citus database is accessible in psql through the postgres user:

::

  sudo -i -u postgres psql
