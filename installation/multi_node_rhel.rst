.. highlight:: bash

.. _production_rhel:

Fedora, CentOS, or Red Hat
==========================

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines from RPM packages.

.. _production_rhel_all_nodes:

Steps to be executed on all nodes
---------------------------------

**1. Add repository**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/rpm.sh | sudo bash

.. _post_install:

**2. Install PostgreSQL + Citus and initialize a database**

::

  # install PostgreSQL with Citus extension
  sudo yum install -y citus111_15
  # initialize system database (using RHEL 6 vs 7 method as necessary)
  sudo service postgresql-15 initdb || sudo /usr/pgsql-15/bin/postgresql-15-setup initdb
  # preload citus extension
  echo "shared_preload_libraries = 'citus'" | sudo tee -a /var/lib/pgsql/15/data/postgresql.conf

PostgreSQL adds version-specific binaries in `/usr/pgsql-15/bin`, but you'll usually just need psql, whose latest version is added to your path, and managing the server itself can be done with the *service* command.

.. _post_enterprise_rhel:

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo vi /var/lib/pgsql/15/data/postgresql.conf

::

  # Uncomment listen_addresses for the changes to take effect
  listen_addresses = '*'

::

  sudo vi /var/lib/pgsql/15/data/pg_hba.conf

::

  # Allow access to nodes in the local network
  host    all             postgres        10.0.0.0/8              scram-sha-256

The coordinator node needs to know roles' passwords in order to communicate with the workers. Our :ref:`cloud_topic` keeps track of that kind of information for you. However, in Citus Community Edition the authentication information has to be maintained in a `.pgpass <https://www.postgresql.org/docs/current/static/libpq-pgpass.html>`_ file. Edit .pgpass in the postgres user's home directory, with a line for each combination of worker address and role:

::

  hostname:port:database:username:password

Sometimes workers need to connect to one another, such as during :ref:`repartition joins <repartition_joins>`. Thus each worker node requires a copy of the .pgpass file, and the password for the ``postgres`` user must be set on each node as well:

::

  sudo -i -u postgres psql -c "ALTER ROLE postgres WITH PASSWORD 'your_password';

**4. Start database servers, create Citus extension**

::

  # start the db server
  sudo service postgresql-15 restart
  # and make it start automatically when computer does
  sudo chkconfig postgresql-15 on

You must add the Citus extension to **every database** you would like to use in a cluster. The following example adds the extension to the default database which is named `postgres`.

::

  sudo -i -u postgres psql -c "CREATE EXTENSION citus;"

.. _production_rhel_coordinator_node:

Steps to be executed on the coordinator node
--------------------------------------------

The steps listed below must be executed **only** on the coordinator node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the coordinator about its workers. To add this information,
we call a UDF which adds the node information to the pg_dist_node
catalog table, which the coordinator uses to get the list of worker
nodes. For our example, we assume that there are two workers (named
worker-101, worker-102). Add the workers' DNS names (or IP addresses)
and server ports to the table.

::

  # Register the hostname that future workers will use to connect
  # to the coordinator node.
  #
  # You'll need to change the example, 'coord.example.com',
  # to match the actual hostname

  sudo -i -u postgres psql -c \
    "SELECT citus_set_coordinator_host('coord.example.com', 5432);"

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
