.. highlight:: bash

.. _production_deb:

Ubuntu or Debian
================

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines using deb packages.

.. _production_deb_all_nodes:

Steps to be executed on all nodes
---------------------------------

**1. Add repository**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/deb.sh | sudo bash

.. _post_install:

**2. Install PostgreSQL + Citus and initialize a database**

::

  # install the server and initialize db
  sudo apt-get -y install postgresql-14-citus-beta-11.0

  # preload citus extension
  sudo pg_conftool 14 main set shared_preload_libraries citus

This installs centralized configuration in `/etc/postgresql/14/main`, and creates a database in `/var/lib/postgresql/14/main`.

.. _post_enterprise_deb:

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo pg_conftool 14 main set listen_addresses '*'

::

  sudo vi /etc/postgresql/14/main/pg_hba.conf

::

  # Allow unrestricted access to nodes in the local network. The following ranges
  # correspond to 24, 20, and 16-bit blocks in Private IPv4 address spaces.
  host    all             all             10.0.0.0/8              trust

  # Also allow the host unrestricted access to connect to itself
  host    all             all             127.0.0.1/32            trust
  host    all             all             ::1/128                 trust

.. note::
  Your DNS settings may differ. Also these settings are too permissive for some environments, see our notes about :ref:`worker_security`. The PostgreSQL manual `explains how <http://www.postgresql.org/docs/current/static/auth-pg-hba-conf.html>`_ to make them more restrictive.

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

.. _production_deb_coordinator_node:

Steps to be executed on the coordinator node
--------------------------------------------

The steps listed below must be executed **only** on the coordinator node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the coordinator about its workers. To add this information,
we call a UDF which adds the node information to the pg_dist_node
catalog table. For our example, we assume that there are two workers
(named worker-101, worker-102). Add the workers' DNS names (or IP
addresses) and server ports to the table.

::

  # Register the hostname that future workers will use to connect
  # to the coordinator node.
  #
  # You'll need to change the example, 'coord.example.com',
  # to match the actual hostname

  sudo -i -u postgres psql -c \
    "SELECT citus_set_coordinator_host('coord.example.com', 5432);

  # Add the worker nodes.
  #
  # Similarly, you'll need to change 'worker-101' and 'worker-102' to the
  # actual hostnames

  sudo -i -u postgres psql -c "SELECT * from citus_add_node('worker-101', 5432);"
  sudo -i -u postgres psql -c "SELECT * from citus_add_node('worker-102', 5432);"

**2. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the coordinator node has
picked up the desired worker configuration. This command when run in the psql
shell should output the worker nodes we added to the pg_dist_node table above.

::

  sudo -i -u postgres psql -c "SELECT * FROM citus_get_active_worker_nodes();"

**Ready to use Citus**

At this step, you have completed the installation process and are ready to use your Citus cluster. The new Citus database is accessible in psql through the postgres user:

::

  sudo -i -u postgres psql
