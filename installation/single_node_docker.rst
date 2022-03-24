.. _single_node_docker:

Docker (Mac or Linux)
=====================

.. note::

   **The Docker image is intended for development/testing purposes only**, and
   has not been prepared for production use.

You can start Citus in Docker with one command:

.. code-block:: bash

  # start the image
  docker run -d --name citus -p 5432:5432 -e POSTGRES_PASSWORD=mypass \
             citusdata/citus:11.0-beta

  # verify it's running, and that Citus is installed:
  psql -U postgres -h localhost -d postgres -c "SELECT * FROM citus_version();"

You should see the latest version of Citus.

Once you have the cluster up and running, you can visit our tutorials on :ref:`multi-tenant applications <multi_tenant_tutorial>` or :ref:`real-time analytics <real_time_analytics_tutorial>` to get started with Citus in minutes.

.. note::

  If you already have PostgreSQL running on your machine you may encounter this
  error when starting the Docker containers:

  .. code::

    Error starting userland proxy:
    Bind for 0.0.0.0:5432: unexpected error address already in use

  This is because the Citus image attempts to bind to the standard PostgreSQL
  port 5432. To fix this, choose a different port with the -p option. You will
  need to also use the new port in the psql command below as well.
