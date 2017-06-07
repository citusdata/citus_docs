.. _cloud_overview:

Overview
========

Citus Cloud is a fully managed hosted version of Citus Enterprise edition on top of AWS. Citus Cloud comes with the benefit of Citus allowing you to easily scale out your memory and processing power, without having to worry about keeping it up and running.

Provisioning
############

Once you've created your account at `https://console.citusdata.com <https://console.citusdata.com>`_ you can provision your Citus cluster. When you login you'll be at the home of the dashboard, and from here you can click New Formation to begin your formation creation. 

.. image:: ../images/cloud_provisioning.png

Configuring Your Plan
---------------------

Citus Cloud plans vary based on the size of your primary node, size of your distributed nodes, number of distributed nodes and whether you have high availability or not. From within the Citus console you can configure your plan or you can preview what it might look like within the `pricing calculator <https://console.citusdata.com/pricing>`_.

The key items you'll care about for each node:

- Storage - All nodes come with 512 GB of storage
- Memory - The memory on each node varies based on the size of node you select
- Cores - The cores on each node varies based on the size of node you select

Connecting to Citus Cloud
#########################

Applications connect to Citus the same way they would PostgreSQL, using a `connection URI <https://www.postgresql.org/docs/current/static/libpq-connect.html#AEN45571>`_. This is a string which includes network and authentication information, and has the form:

::

  postgresql://[user[:password]@][host][:port][/dbname][?param1=value1&...]

The connection string for each Cloud Formation is provided on the Overview tab in Citus Console.

.. image:: ../images/cloud-overview-1.png

By default the URL displays only the hostname of the connection, but the full URL is available by clicking the "Show Full URL" link.

.. image:: ../images/cloud-overview-2.png

For security Citus Cloud accepts only SSL connections, which is why the URL contains the :code:`?sslmode=require` parameter. To avoid a man-in-the-middle attack, you can also verify that the server certificate is correct. Download the official `Citus Cloud certificate <https://console.citusdata.com/citus.crt>`_ and refer to it in connection string parameters:

::

  ?sslrootcert=/location/to/citus.crt&sslmode=verify-full

The string may need to be quoted in your shell to preserve the ampersand.

.. note::

  Database clients must support SSL to connect to Citus Cloud. In particular :code:`psql` needs to be compiled :code:`--with-openssl` if building PostgreSQL from source.

A coordinator node on Citus Cloud has a hard limit of three hundred simultaneous active connections to limit memory consumption. If more connections are required, change the port in the connection URL from 5432 to 6432. This will connect to PgBouncer rather than directly to the coordinator, allowing up to roughly two thousand simultaneous connections. The coordinator can still only process three hundred at a time, but more can connect and PgBouncer will queue them.

To measure the number of active connections at a given time, run:

.. code-block:: postgresql

  SELECT COUNT(*)
    FROM pg_stat_activity
   WHERE state <> 'idle';

High Availability
#################

The high availability option on a cluster automatically provisions instance stand-bys. These stand-bys receive streaming updates directly from each of the leader nodes. We continuously monitor the leader nodes to ensure they're available and healthy. In the event of a failure we automatically switch to the stand-bys.

Note that your data is replicated to S3 with and without enabling high availability. This allows disaster recovery and reduces the risk of data loss. Although the data is safe either way, we suggest enabling high availability if you cannot tolerate up to one hour of downtime in the rare occurrence of an instance failure. We do not offer a SLA on uptime.

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'overview', section: 'cloud'});
  </script>
