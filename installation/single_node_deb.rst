.. _single_node_deb:

Single-node setup from .deb packages (Ubuntu / Debian)
=======================================================

This section describes the procedure for setting up a CitusDB cluster on a single node from .deb packages.

We recommend using Ubuntu 12.04+ or Debian 7+ for running CitusDB. However, older versions of Ubuntu 10.04+ and Debian 6+ are also supported.


**1. Download CitusDB packages**

Please note that by downloading the packages below, you agree that you have read, understand and accept the `CitusDB License Agreement <https://www.citusdata.com/license-agreement>`_.
	
::

	wget https://packages.citusdata.com/readline-6.0/citusdb-4.0.1-1.amd64.deb
	wget https://packages.citusdata.com/contrib/citusdb-contrib-4.0.1-1.amd64.deb

Note: We also download the contrib package in addition to the core CitusDB package. The contrib package contains extensions to core CitusDB, such as the pg_shard extension for real-time inserts, the hstore type, HyperLogLog module for distinct count approximations, and administration tools such as shard rebalancer and pg_upgrade.

**2. Install CitusDB packages using the debian package manager**

::

	sudo dpkg --install citusdb-4.0.1-1.amd64.deb
	sudo dpkg --install citusdb-contrib-4.0.1-1.amd64.deb

The CitusDB package puts all binaries under /opt/citusdb/4.0, and also creates a data subdirectory to store the newly initialized database's contents. The data directory created is owned by the current user. If CitusDB cannot find a non-root user, then the directory is owned by the ‘postgres’ user.

**3. Setup worker database instances**

In the single node setup, we use multiple database instances on the same node to demonstrate CitusDB’s distributed logic. We use the already installed database as the master, and then initialize two more worker nodes. Note that we use the standard postgres `initdb <http://www.postgresql.org/docs/9.4/static/app-initdb.html>`_  utility to initialize the databases.

::

	/opt/citusdb/4.0/bin/initdb -D /opt/citusdb/4.0/data.9700
	/opt/citusdb/4.0/bin/initdb -D /opt/citusdb/4.0/data.9701

**4. Add worker node information**

CitusDB uses a configuration file to inform the master node about the worker databases. To add this information, we append the worker database names and server ports to the pg_worker_list.conf file in the data directory.

::

	echo 'localhost 9700' >> /opt/citusdb/4.0/data/pg_worker_list.conf
	echo 'localhost 9701' >> /opt/citusdb/4.0/data/pg_worker_list.conf

Note that you can also add this information by editing the file using your favorite editor.

**5. Add pg_shard related configuration to enable real time inserts**

::

	vi /opt/citusdb/4.0/data/postgresql.conf

::

        # Add the two below lines to the config file
	shared_preload_libraries = 'pg_shard'
        pg_shard.use_citusdb_select_logic = true

**6. Start the master and worker databases**

::

/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data -l logfile start
/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data.9700 -o "-p 9700" -l logfile.9700 start
/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data.9701 -o "-p 9701" -l logfile.9701 start

Note that we use the standard postgresql pg_ctl utility to start the database. You can use the same utility to stop, restart or reload the cluster as specified in the `PostgreSQL documentation <http://www.postgresql.org/docs/9.4/static/app-pg-ctl.html>`_.

**7. Create the pg_shard extension on the master node**

::

    /opt/citusdb/4.0/bin/psql -h localhost -d postgres

::

	CREATE EXTENSION pg_shard;

**8. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the master node has picked up the desired worker configuration. This command when run in the psql shell should output the worker nodes mentioned in the pg_worker_list.conf file.

::

	select * from master_get_active_worker_nodes();

**Ready to use CitusDB**

At this step, you have completed the installation process and are ready to use CitusDB. To help you get started, we have an :ref:`examples_index` guide which has instructions on setting up a CitusDB cluster with sample data in minutes. You can also visit the :ref:`user_guide_index` section of our documentation to learn about CitusDB commands in detail.
