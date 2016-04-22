.. _single_node_docker:

Docker single-node setup
=======================================================

This section describes setting up a Citus cluster on a single node using docker-compose.

**1. Install docker and docker-compose**

The easiest way to install docker-compose on Mac or Windows is to use the `docker toolbox <https://www.docker.com/products/docker-toolbox>`_ installer. Ubuntu users can follow `this guide <https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-compose-on-ubuntu-14-04>`_; other Linux distros have a similar procedure.

Note that Docker runs in a virtual machine on Mac, and to use it in your terminal you first must run

::

	# for mac only
	eval $(docker-machine env default)

This exports environment variables which tell the docker command-line tools how to connect to the virtual machine.

**2. Start the Citus Cluster**

Citus uses docker-compose to run and connect containers holding the database master node, workers, and a persistent data volume. To create a local cluster download our docker-compose configuration file and run it

::

	wget https://raw.githubusercontent.com/citusdata/docker/master/docker-compose.yml
	docker-compose -p citus up -d

The first time you start the cluster it builds its containers. Subsequent startups take a
matter of seconds.

**3. Verify that installation has succeeded**


To verify that the installation has succeeded we check that the master node has picked up the desired worker configuration. First start the psql shell on the master node:

::

	docker exec -it citus_master psql -U postgres

Then run this query:

::

	select * from master_get_active_worker_nodes();

You should see a row for each worker node including the node name and port.

**4. Download Tutorials**

We created tutorials for you that show example use-cases. To run these tutorials, you'll
first need to download a tarball for your platform.

* `Linux Tutorials <https://s3.amazonaws.com/packages.citusdata.com/tutorials/try-citus-4.tar.gz>`_
* `OS X Tutorials <https://s3.amazonaws.com/packages.citusdata.com/tutorials/try-citus-osx-3.tar.gz>`_

Download and unzip this tutorial into a directory of your choosing.

**5. Go run some queries**

Your cluster is running and eagerly waiting for data. We created tutorials for you that
show example use-cases. :ref:`Visit our tutorials to feed data into your Citus cluster and
run example queries within minutes <tut_real_time>`.
