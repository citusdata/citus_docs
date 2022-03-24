.. highlight:: bash

.. _single_node_deb:

Ubuntu or Debian
================

This section describes the steps needed to set up a single-node Citus cluster on your own Linux machine from deb packages.

**1. Install PostgreSQL 14 and the Citus extension**

.. code-block:: sh

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/deb.sh | sudo bash

  # install the server and initialize db
  sudo apt-get -y install postgresql-14-citus-beta-11.0


.. _post_install:

**2. Initialize the Cluster**

Let's create a new database on disk. For convenience in using PostgreSQL Unix domain socket connections, we'll use the postgres user.

.. code-block:: sh

  # this user has access to sockets in /var/run/postgresql
  sudo su - postgres

  # include path to postgres binaries
  export PATH=$PATH:/usr/lib/postgresql/14/bin

  cd ~
  mkdir citus
  initdb -D citus

Citus is a Postgres extension. To tell Postgres to use this extension you'll need to add it to a configuration variable called ``shared_preload_libraries``:

.. code-block:: sh

  echo "shared_preload_libraries = 'citus'" >> citus/postgresql.conf

**3. Start the database server**

Finally, we'll start an instance of PostgreSQL for the new directory:

.. code-block:: sh

  pg_ctl -D citus -o "-p 9700" -l citus_logfile start

Above you added Citus to ``shared_preload_libraries``. That lets it hook into some deep parts of Postgres, swapping out the query planner and executor.  Here, we load the user-facing side of Citus (such as the functions you'll soon call):

.. code-block:: sh

  psql -p 9700 -c "CREATE EXTENSION citus;"

**4. Verify that installation has succeeded**

To verify that the installation has succeeded, and Citus is installed:

.. code-block:: sh

  psql -p 9700 -c "select citus_version();"

You should see details of the Citus extension.

At this step, you have completed the installation process and are ready to use your Citus cluster. To help you get started, we have a :ref:`tutorial<multi_tenant_tutorial>` which has instructions on setting up a Citus cluster with sample data in minutes.
