.. _data_migration:

Data Migration
==============

Migrating from one database to another has traditionally been difficult. There are two traditional approaches: using a dump and restore that takes downtime, or updating application logic to write to two databases and then switch to the new one.

Now there's an easier way. PostgreSQL 9.4 added logical replication to stream data to a new database even while the existing database continues to sustain application load. It's as if the application automatically writes to two databases rather than one, except with perfect transactional logic.

We have streamlined logical replication on :ref:`Citus Cloud <cloud_overview>` with a process called Citus Warp. To do a warp, we connect the coordinator node of a Citus cluster to an existing database through VPC peering or IP white-listing, and begin replication.

Using Citus Warp
----------------

Here's the high level overview of the process:

1. Duplicate structure of the schema on a destination Citus cluster
2. Enable logical replication in the source database
3. Allow a network connection from Citus coordinator node to source
4. Make sure no changes will happen to the schema of the source (modifying data is fine, but not structure)
5. Contact us to run the warp

1. Duplicate schema
~~~~~~~~~~~~~~~~~~~

The first step in migrating data to Citus is making sure that the schemas match exactly, at least for the tables you choose to migrate. One way to do this is by running ``pg_dump --schema-only`` against the source database. Replay the output on the coordinator Citus node. Another way to is to run application migration scripts against the destination database.

All tables that you wish to migrate must have primary keys. The corresponding destination tables must have primary keys as well, the only difference being that those keys are allowed to be composition to contain the distribution column as well, as described in :ref:`mt_schema_migration`.

Also be sure to distribute tables across the cluster prior to starting a warp so that the data doesn't have to fit on the coordinator node alone.

2. Enable logical replication
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Some hosted databases such as Amazon RDS require enabling replication by changing a server configuration parameter. On RDS you will need to create a new parameter group, set ``rds.logical_replication = 1`` in it, then change set the parameter group as the active one. Applying the change requires a database server reboot, which can be scheduled for the next maintenance window.

3. Open access for network connection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the Cloud console, identify the hostname (it ends in ``db.citusdata.com``). Dig the hostname to find its IP address:

.. code-block:: bash

  dig +short <hostname> A

On RDS, edit the inbound database security group to add a custom TCP rule:

Protocol
  TCP
Port Range
  5432
Source
  <citus ip>/32

This white-lists the IP address of the Citus coordinator node to make an inbound connection. An alternate way to connect the two is to establish peering between their virtual private clouds. We can help set that up if desired.

4. Freeze schema changes
~~~~~~~~~~~~~~~~~~~~~~~~

Put a freeze on the structure of the source database, telling application developers not to modify it. Mismatched table columns/types can confuse the replication process.

5. Run the Warp
~~~~~~~~~~~~~~~

Contact us and a Cloud engineer will connect to your database with Citus Warp to create a basebackup, open a replication slot, and begin the replication. We can include/exclude your choice of tables in the migration.

During the first stage, creating a basebackup, the Postgres write-ahead log (WAL) may grow substantially if the database is under write load. Make sure you have at least 20% free space on disk during this process. Once the backup is complete and replication begins then the database will be able to shrink the WAL again.

When the replication has caught up with the current state of the source database, the application is free to connect to the new database instead. Any stray updates from the source database will continue to be reflected in the destination.

Finally, when the application is pointing to the new database and no further changes are happening on the source database, contact us again to remove the replication slot. The migration is complete.
