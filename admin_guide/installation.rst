Installation
############

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

.. _production:

Multi-Machine Production Cluster
================================

.. _multi_machine_cloud:

Citus Cloud
-----------

Citus Cloud is a fully managed "Citus-as-a-Service" built on top of Amazon Web Services. It's an easy way to provision and monitor a high-availability cluster.

.. raw:: html

  <p class="wy-text-center">
    <a href="https://www.citusdata.com/cloud" class="btn btn-neutral"
       onclick="trackOutboundLink('https://www.citusdata.com/cloud'); return false;">
      Try Citus Cloud
      <span class="fa fa-cloud"></span>
    </a>
  </p>


.. _production_deb:

Ubuntu or Debian
----------------

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines using deb packages.

.. _production_deb_all_nodes:

Steps to be executed on all nodes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**1. Add repository**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/deb.sh | sudo bash

.. _post_install:

**2. Install PostgreSQL + Citus and initialize a database**

::

  # install the server and initialize db
  sudo apt-get -y install postgresql-10-citus-7.3

  # preload citus extension
  sudo pg_conftool 10 main set shared_preload_libraries citus

This installs centralized configuration in `/etc/postgresql/10/main`, and creates a database in `/var/lib/postgresql/10/main`.

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo pg_conftool 10 main set listen_addresses '*'

::

  sudo vi /etc/postgresql/10/main/pg_hba.conf

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
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The steps listed below must be executed **only** on the coordinator node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the coordinator about its workers. To add this information,
we call a UDF which adds the node information to the pg_dist_node
catalog table. For our example, we assume that there are two workers
(named worker-101, worker-102). Add the workers' DNS names (or IP
addresses) and server ports to the table.

::

  sudo -i -u postgres psql -c "SELECT * from master_add_node('worker-101', 5432);"
  sudo -i -u postgres psql -c "SELECT * from master_add_node('worker-102', 5432);"

**2. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the coordinator node has
picked up the desired worker configuration. This command when run in the psql
shell should output the worker nodes we added to the pg_dist_node table above.

::

  sudo -i -u postgres psql -c "SELECT * FROM master_get_active_worker_nodes();"

**Ready to use Citus**

At this step, you have completed the installation process and are ready to use your Citus cluster. The new Citus database is accessible in psql through the postgres user:

::

  sudo -i -u postgres psql

.. note::

  Please note that Citus reports anonymous information about your cluster to the Citus Data company servers. To learn more about what information is collected and how to opt out of it, see :ref:`phone_home`.

.. _production_rhel:

Fedora, CentOS, or Red Hat
--------------------------

This section describes the steps needed to set up a multi-node Citus cluster on your own Linux machines from RPM packages.

.. _production_rhel_all_nodes:

Steps to be executed on all nodes
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**1. Add repository**

::

  # Add Citus repository for package manager
  curl https://install.citusdata.com/community/rpm.sh | sudo bash

.. _post_install:

**2. Install PostgreSQL + Citus and initialize a database**

::

  # install PostgreSQL with Citus extension
  sudo yum install -y citus73_10
  # initialize system database (using RHEL 6 vs 7 method as necessary)
  sudo service postgresql-10 initdb || sudo /usr/pgsql-10/bin/postgresql-10-setup initdb
  # preload citus extension
  echo "shared_preload_libraries = 'citus'" | sudo tee -a /var/lib/pgsql/10/data/postgresql.conf

PostgreSQL adds version-specific binaries in `/usr/pgsql-10/bin`, but you'll usually just need psql, whose latest version is added to your path, and managing the server itself can be done with the *service* command.

**3. Configure connection and authentication**

Before starting the database let's change its access permissions. By default the database server listens only to clients on localhost. As a part of this step, we instruct it to listen on all IP interfaces, and then configure the client authentication file to allow all incoming connections from the local network.

::

  sudo vi /var/lib/pgsql/10/data/postgresql.conf

::

  # Uncomment listen_addresses for the changes to take effect
  listen_addresses = '*'

::

  sudo vi /var/lib/pgsql/10/data/pg_hba.conf

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
  sudo service postgresql-10 restart
  # and make it start automatically when computer does
  sudo chkconfig postgresql-10 on

You must add the Citus extension to **every database** you would like to use in a cluster. The following example adds the extension to the default database which is named `postgres`.

::

  sudo -i -u postgres psql -c "CREATE EXTENSION citus;"

.. _production_rhel_coordinator_node:

Steps to be executed on the coordinator node
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The steps listed below must be executed **only** on the coordinator node after the previously mentioned steps have been executed.

**1. Add worker node information**

We need to inform the coordinator about its workers. To add this information,
we call a UDF which adds the node information to the pg_dist_node
catalog table, which the coordinator uses to get the list of worker
nodes. For our example, we assume that there are two workers (named
worker-101, worker-102). Add the workers' DNS names (or IP addresses)
and server ports to the table.

::

  sudo -i -u postgres psql -c "SELECT * from master_add_node('worker-101', 5432);"
  sudo -i -u postgres psql -c "SELECT * from master_add_node('worker-102', 5432);"

**2. Verify that installation has succeeded**

To verify that the installation has succeeded, we check that the coordinator node has
picked up the desired worker configuration. This command when run in the psql
shell should output the worker nodes we added to the pg_dist_node table above.

::

  sudo -i -u postgres psql -c "SELECT * FROM master_get_active_worker_nodes();"

**Ready to use Citus**

At this step, you have completed the installation process and are ready to use your Citus cluster. The new Citus database is accessible in psql through the postgres user:

::

  sudo -i -u postgres psql

.. note::

  Please note that Citus reports anonymous information about your cluster to the Citus Data company servers. To learn more about what information is collected and how to opt out of it, see :ref:`phone_home`.

.. _multi_machine_manual:

CloudFormation
--------------

Alternately you can manage a Citus cluster manually on `EC2 <http://aws.amazon.com/ec2/>`_ instances using CloudFormation. The CloudFormation template for Citus enables users to start a Citus cluster on AWS in just a few clicks, with also cstore_fdw extension for columnar storage is pre-installed. The template automates the installation and configuration process so that the users don’t need to do any extra configuration steps while installing Citus.

Please ensure that you have an active AWS account and an `Amazon EC2 key pair <http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html>`_ before proceeding with the next steps.

**Introduction**

`CloudFormation <http://aws.amazon.com/cloudformation/>`_ lets you create a "stack" of AWS resources, such as EC2 instances and security groups, from a template defined in a JSON file. You can create multiple stacks from the same template without conflict, as long as they have unique stack names.

Below, we explain in detail the steps required to setup a multi-node Citus cluster on AWS.

**1. Start a Citus cluster**

.. raw:: html 
  
 <p>To begin, you can start a Citus cluster using CloudFormation by clicking <a href="https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=Citus&templateURL=https:%2F%2Fcitus-deployment.s3.amazonaws.com%2Faws%2Fcitus7%2Fcloudformation%2Fcitus-7.3.0.json" onclick="trackOutboundLink('https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=Citus&templateURL=https:%2F%2Fcitus-deployment.s3.amazonaws.com%2Faws%2Fcitus7%2Fcloudformation%2Fcitus-7.3.0.json'); return false;">here</a>. This will take you directly to the AWS CloudFormation console.</p>


.. note::
  You might need to login to AWS at this step if you aren’t already logged in.

**2. Select Citus template**

You will see select template screen. Citus template is already selected, just click Next.

**3. Fill the form with details about your cluster**

In the form, pick a unique name for your stack. You can customize your cluster setup by setting availability zones, number of workers and the instance types. You also need to fill in the AWS keypair which you will use to access the cluster.

.. image:: ../images/aws_parameters.png

.. note::
  Please ensure that you choose unique names for all your clusters. Otherwise, the cluster creation may fail with the error “Template_name template already created”.

.. note::
  If you want to launch a cluster in a region other than US East, you can update the region in the top-right corner of the AWS console as shown below.

.. image:: ../images/aws_region.png
	:scale: 50 %
	:align: center


**4. Acknowledge IAM capabilities**

The next screen displays Tags and a few advanced options. For simplicity, we use the default options and click Next.

Finally, you need to acknowledge IAM capabilities, which give the coordinator node limited access to the EC2 APIs to obtain the list of worker IPs. Your AWS account needs to have IAM access to perform this step. After ticking the checkbox, you can click on Create.

.. image:: ../images/aws_iam.png


**5. Cluster launching**

After the above steps, you will be redirected to the CloudFormation console. You can click the refresh button on the top-right to view your stack. In about 10 minutes, stack creation will complete and the hostname of the coordinator node will appear in the Outputs tab. 

.. image:: ../images/aws_cluster_launch.png

.. note::
  Sometimes, you might not see the outputs tab on your screen by default. In that case, you should click on “restore” from the menu on the bottom right of your screen.
 
.. image:: ../images/aws_restore_icon.png
	:align: center

**Troubleshooting:**

You can use the cloudformation console shown above to monitor your cluster.

If something goes wrong during set-up, the stack will be rolled back but not deleted. In that case, you can either use a different stack name or delete the old stack before creating a new one with the same name.

**6. Login to the cluster**

Once the cluster creation completes, you can immediately connect to the coordinator node using SSH with username ec2-user and the keypair you filled in. For example:

::

	ssh -i your-keypair.pem ec2-user@ec2-54-82-70-31.compute-1.amazonaws.com


**7. Ready to use the cluster**

At this step, you have completed the installation process and are ready to use the Citus cluster. You can now login to the coordinator node and start executing commands. The command below, when run in the psql shell, should output the worker nodes mentioned in the pg_dist_node.

::

	/usr/pgsql-9.6/bin/psql -h localhost -d postgres
	select * from master_get_active_worker_nodes();


**8. Cluster notes**

The template automatically tunes the system configuration for Citus and sets up RAID on the SSD drives where appropriate, making it a great starting point even for production systems.

The database and its configuration files are stored in /data/base. So, to change any configuration parameters, you need to update the postgresql.conf file at /data/base/postgresql.conf.

Similarly to restart the database, you can use the command:

::

	/usr/pgsql-9.6/bin/pg_ctl -D /data/base -l logfile restart

.. note::
  You typically want to avoid making changes to resources created by CloudFormation, such as terminating EC2 instances. To shut the cluster down, you can simply delete the stack in the CloudFormation console.
