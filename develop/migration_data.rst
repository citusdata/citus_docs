.. _data_migration:

Migrate Data
============

At this time, having updated the database schema and application queries to work with Citus, you're ready for the final step. It's time to migrate data to the Citus cluster and cut over the application to its new database.

The data migration path is dependent on downtime requirements and data size, but generally falls into one of the following two categories.

Databases under 200GB
---------------------

Smaller environments that can tolerate a little downtime can use a simple pg_dump/pg_restore process.

* Put the application in maintenance mode
* Dump the old database using pg_dump
* Disallow connections to old database
* Import into Citus using pg_restore
* Test application
* Launch!

Documentation request: Page detailing this process

Databases over 200GB
--------------------

Larger environments can use Citus Warp for online replication. Citus Warp allows you to stream changes from a PostgreSQL source database into a :ref:`Citus Cloud <cloud_overview>` cluster as they happen. It's as if the application automatically writes to two databases rather than one, except with perfect transactional logic. Citus Warp works with Postgres versions 9.4 and above which have the `logical_decoding` plugin enabled (this is supported on Amazon RDS as long as you're at version 9.4 or higher).

For this process we strongly recommend contacting us by opening a ticket, contacting one of our solutions engineers on Slack, or whatever method works for you. To do a warp, we connect the coordinator node of a Citus cluster to an existing database through VPC peering or IP white-listing, and begin replication.

Here are the steps you need to perform before starting the Citus Warp process:

1. Duplicate the structure of the schema on a destination Citus cluster
2. Enable logical replication in the source database
3. Allow a network connection from Citus coordinator node to source
4. Contact us to begin the replication

Duplicate schema
~~~~~~~~~~~~~~~~

The first step in migrating data to Citus is making sure that the schemas match exactly, at least for the tables you choose to migrate. One way to do this is by running ``pg_dump --schema-only`` against the source database. Replay the output on the coordinator Citus node. Another way to is to run application migration scripts against the destination database.

All tables that you wish to migrate must have primary keys. The corresponding destination tables must have primary keys as well, the only difference being that those keys are allowed to be composite to contain the distribution column as well, as described in :ref:`mt_schema_migration`.

Also be sure to :ref:`distribute tables <ddl>` across the cluster prior to starting replication so that the data doesn't have to fit on the coordinator node alone.

Enable logical replication
~~~~~~~~~~~~~~~~~~~~~~~~~~

Some hosted databases such as Amazon RDS require enabling replication by changing a server configuration parameter. On RDS you will need to create a new parameter group, set ``rds.logical_replication = 1`` in it, then make the parameter group the active one. Applying the change requires a database server reboot, which can be scheduled for the next maintenance window.

If you're administering your own PostgreSQL installation, add these settings to postgresql.conf:

.. code-block:: shell

  wal_level = logical
  max_replication_slots = 5 # has to be > 0
  max_wal_senders = 5       # has to be > 0

A database restart is required for the changes to take effect.

Open access for network connection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the Cloud console, identify the hostname (it ends in ``db.citusdata.com``). Dig the hostname to find its IP address:

.. code-block:: bash

  dig +short <hostname> A

If you're using RDS, edit the inbound database security group to add a custom TCP rule:

Protocol
  TCP
Port Range
  5432
Source
  <citus ip>/32

This white-lists the IP address of the Citus coordinator node to make an inbound connection. An alternate way to connect the two is to establish peering between their VPCs. We can help set that up if desired.

Begin Replication
~~~~~~~~~~~~~~~~~

Contact us by opening a support ticket in the Citus Cloud console. A Cloud engineer will connect to your database with Citus Warp to create a basebackup, open a replication slot, and begin the replication. We can include/exclude your choice of tables in the migration.

During the first stage, creating a basebackup, the Postgres write-ahead log (WAL) may grow substantially if the database is under write load. Make sure you have sufficient disk space on the source database before starting this process. We recommend 100GB free or 20% of total disk space, whichever is greater. Once the backup is complete and replication begins then the database will be able to archive unused WAL files again.

Some database schema changes are incompatible with an ongoing replication. Changing the structure of tables under replication can cause the process to stop. Cloud engineers would then need to manually restart the replication from the beginning. That costs time, so we recommend freezing the schema during replication.

Switch over to Citus and stop all connections to old database
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When the replication has caught up with the current state of the source database, there is one more thing to do. Due to the nature of the replication process, sequence values don't get updated correctly on the destination databases. In order to have the correct sequence value for e.g. an id column, you need to manually adjust the sequence values before turning on writes to the destination database.

Once this is all complete, the application is ready to connect to the new database. We do not recommend writing to both the source and destination database at the same time.

When the application has cut over to the new database and no further changes are happening on the source database, contact us again to remove the replication slot. The migration is complete.
