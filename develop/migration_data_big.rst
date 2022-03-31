Big Database Migration
======================

Larger environments can use tools like `Citus Warp <https://www.citusdata.com/blog/2017/12/08/citus-warp-pain-free-migrations/>`_, `Debezium <https://debezium.io/>`_, `Striim <https://www.striim.com/partners/striim-for-microsoft-azure/>`_ or `HVR <https://www.hvr-software.com/platforms/postgresql/>`_ for online replication. These tools allow you to stream changes from a PostgreSQL source database into our :ref:`cloud_topic` on Microsoft Azure. It's as if the application automatically writes to two databases rather than one, except with perfect transactional logic.

For this process we strongly recommend contacting us by `opening a support reauest <https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest>`_. To do the replication, we connect the coordinator node of a Citus cluster to an existing database through VPC peering or IP white-listing, and begin replication.

Here are the steps you need to perform before starting the replication process:

1. Duplicate the structure of the schema on a destination Citus cluster
2. Enable logical replication in the source database
3. Allow a network connection from Citus coordinator node to source
4. Contact us to begin the replication

Duplicate schema
----------------

The first step in migrating data to Citus is making sure that the schemas match exactly, at least for the tables you choose to migrate. One way to do this is by running ``pg_dump --schema-only`` against your development database (the Citus database you used for locally testing the application). Replay the output on the coordinator Citus node. Another way to is to run application migration scripts against the destination database.

All tables that you wish to migrate must have primary keys. The corresponding destination tables must have primary keys as well, the only difference being that those keys are allowed to be composite to contain the distribution column as well, as described in :ref:`mt_schema_migration`.

Also be sure to :ref:`distribute tables <ddl>` across the cluster prior to starting replication so that the data doesn't have to fit on the coordinator node alone.

Enable logical replication
--------------------------

Some hosted databases such as Amazon RDS require enabling replication by changing a server configuration parameter. On RDS you will need to create a new parameter group, set ``rds.logical_replication = 1`` in it, then make the parameter group the active one. Applying the change requires a database server reboot, which can be scheduled for the next maintenance window.

If you're administering your own PostgreSQL installation, add these settings to postgresql.conf:

.. code-block:: shell

  wal_level = logical
  max_replication_slots = 5 # has to be > 0
  max_wal_senders = 5       # has to be > 0

A database restart is required for the changes to take effect.

Open access for network connection
----------------------------------

Identify the IP address for the destination coordinator node. Dig the hostname to find its IP address:

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
-----------------

Contact us by opening a `support ticket <https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest>`_ in the Azure portal. An engineer will connect to your database to perform an intial database dump, open a replication slot, and begin the replication. We can include/exclude your choice of tables in the migration.

During the first stage of replication, the Postgres write-ahead log (WAL) may grow substantially if the database is under write load. Make sure you have sufficient disk space on the source database before starting this process. We recommend 100GB free or 20% of total disk space, whichever is greater. Once the initial dump/restore is complete and replication begins, then the database will be able to archive unused WAL files again.

As the replication proceeds, **pay attention to disk usage on the source database.** If there is a data-type mismatch between the source and destination, or other unexpe cted schema change, the replication can stall. The replication slot can grow indefini tely on the source during a prolonged stall, leading to potential crashes.

Because of the potential for replication stalls, we strongly recommend minimizing sc hema changes while doing replication. If an invasive schema change is required, you will need to stop and try again.

Steps to make an invasive schema change:

1. Ask a support engineer to stop the replication.
2. Change the schema on the source database.
3. Change the schema on the destination database.
4. Begin again.

Switch over to Citus and stop all connections to old database
-------------------------------------------------------------

When the replication has caught up with the current state of the source database, there is one more thing to do. Due to the nature of the replication process, sequence values don't get updated correctly on the destination databases. In order to have the correct sequence value for e.g. an id column, you need to manually adjust the sequence values before turning on writes to the destination database.

Once this is all complete, the application is ready to connect to the new database. We do not recommend writing to both the source and destination database at the same time.

When the application has cut over to the new database and no further changes are happening on the source database, contact us again to remove the replication slot. The migration is complete.
