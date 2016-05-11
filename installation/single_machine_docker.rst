.. _single_machine_docker:

Docker
======

This section describes setting up a Citus cluster on a single machine using docker-compose.

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
