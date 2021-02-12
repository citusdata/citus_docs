.. _single_machine_docker:

Docker (Mac or Linux)
=====================

This section describes setting up single-node Citus using Docker.

.. note::
   **The Docker image is intended for development/testing purposes only**, and
   has not been prepared for production use.

Simply fetch the image and run it:

.. code-block:: bash

  docker run -d --name citus -p 5432:5432 -e POSTGRES_PASSWORD=foo citusdata/citus

The first time you start the Citus, it must build its containers. Subsequent startups take a matter of seconds.

.. note::

  If you already have PostgreSQL running on your machine you may encounter this
  error when starting the Docker containers:

  .. code::

    Error starting userland proxy:
    Bind for 0.0.0.0:5432: unexpected error address already in use

  This is because the Citus image attempts to bind to the standard PostgreSQL
  port 5432. Simply choose a different port with the -p option. You will need
  to also use the new port in the psql command below as well.


**3. Verify that installation has succeeded**

To verify the database is running and has Citus installed, send a command with psql:

.. code-block:: bash

  psql -d postgres -c "SELECT * FROM citus_version();"

You should see the latest version of Citus.

Once you have the cluster up and running, you can visit our tutorials on :ref:`multi-tenant applications <multi_tenant_tutorial>` or :ref:`real-time analytics <real_time_analytics_tutorial>` to get started with Citus in minutes.
