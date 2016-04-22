.. _multi_node_rpm:

Setup multiple node cluster from .rpm packages (Fedora / Centos / Redhat)
--------------------------------------------------------------------------------

This section describes the steps needed to set up a multi-node CitusDB cluster on your own Linux machines from the .rpm packages.

We recommend using Fedora 11+, Redhat 6+ or Centos 6+ for running CitusDB.

**Steps to be executed on all nodes**


**1. Download CitusDB packages**

Please note that by downloading the packages below, you agree that you have read, understand and accept the `CitusDB License Agreement <https://www.citusdata.com/license-agreement>`_.
	
::

	wget https://packages.citusdata.com/readline-6.0/citusdb-4.0.1-1.x86_64.rpm
	wget https://packages.citusdata.com/contrib/citusdb-contrib-4.0.1-1.x86_64.rpm

Note: We also download the contrib package in addition to the core CitusDB package. The contrib package contains extensions to core CitusDB, such as the pg_shard extension for real-time inserts, the hstore type, HyperLogLog module for distinct count approximations, and administration tools such as shard rebalancer and pg_upgrade.

**2. Install CitusDB packages using the rpm package manager**

::

	sudo rpm --install citusdb-4.0.1-1.x86_64.rpm
	sudo rpm --install citusdb-contrib-4.0.1-1.x86_64.rpm

The CitusDB package puts all binaries under /opt/citusdb/4.0, and also creates a data subdirectory to store the newly initialized database's contents. The data directory created is owned by the current user. If CitusDB cannot find a non-root user, then the directory is owned by the ‘postgres’ user.

**3. Configure connection and authentication**

By default, the CitusDB server only listens to clients on localhost. As a part of this step, we instruct CitusDB to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

	vi /opt/citusdb/4.0/data/postgresql.conf

::

	# Uncomment listen_addresses for the changes to take effect
	listen_addresses = '*'

::
	
	vi /opt/citusdb/4.0/data/pg_hba.conf

::

	# Allow unrestricted access to nodes in the local network. The following ranges
	# correspond to 24, 20, and 16-bit blocks in Private IPv4 address spaces.
	host	all         	all         	10.0.0.0/8        	trust

Note: Admittedly, these settings are too permissive for certain types of environments, and the PostgreSQL manual explains in more detail on `how to restrict them further <http://www.postgresql.org/docs/9.4/static/auth-pg-hba-conf.html>`_. 

**4. Start database servers**

Now, we start up all the databases in the cluster.
::

	/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data -l logfile start

Note that we use the standard postgresql pg_ctl utility to start the database. You can use the same utility to stop, restart or reload the cluster as specified in the `PostgreSQL documentation <http://www.postgresql.org/docs/9.4/static/app-pg-ctl.html>`_.

**Steps to be executed on the master node**

These steps must be executed **only** on the master node after the above mentioned steps have been executed.

**5. Add worker node information**

CitusDB uses a configuration file to inform the master node about the worker databases. To add this information, we append the worker database names and server ports to the pg_worker_list.conf file in the data directory. For our example, we assume that there are two workers (worker-101 and worker-102) and add their DNS names and server ports to the list.

::

	echo 'worker-101 5432' >> /opt/citusdb/4.0/data/pg_worker_list.conf
	echo 'worker-102 5432' >> /opt/citusdb/4.0/data/pg_worker_list.conf

Note that you can also add this information by editing the file using your favorite editor.

**6. Add pg_shard related configuration to enable real time inserts**

::

	vi /opt/citusdb/4.0/data/postgresql.conf

::

        # Add the two below lines to the config file
	shared_preload_libraries = 'pg_shard'
        pg_shard.use_citusdb_select_logic = true

**7. Restart the master database**

::
	
	/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data -l logfile restart

**8. Create the pg_shard extension**

::
	
	/opt/citusdb/4.0/bin/psql -h localhost -d postgres

::
	
	CREATE EXTENSION pg_shard;


**9. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the master node has picked up the desired worker configuration. This command when run in the psql shell should output the worker nodes mentioned in the pg_worker_list.conf file.

::
	
	select * from master_get_active_worker_nodes();

**Ready to use CitusDB**

At this step, you have completed the installation process and are ready to use your CitusDB cluster. To help you get started, we have an :ref:`examples_index` guide which has instructions on setting up a CitusDB cluster with sample data in minutes. You can also visit the :ref:`user_guide_index` section of our documentation to learn about CitusDB commands in detail.

