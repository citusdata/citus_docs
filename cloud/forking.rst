Forking
#######

Forking a Citus Cloud formation makes a copy of the cluster's data at an instant in time and produces a new formation in precisely that state. It allows you to change, query, or generally experiment with production data in a separate protected environment. Fork creation runs quickly, and you can do it as often as you want without causing any extra load on the original cluster. This is because forking doesn't query the cluster, rather it taps into the write-ahead logs for each database in the formation.

How to Fork a Formation
-----------------------

Citus Cloud makes forking easy. The control panel for each formation has a "Fork" tab. Go there and enter the name, region, and node sizing information for the destination cluster.

.. image:: ../images/cloud-fork.png

Shortly after you click "Fork Formation," the new formation will appear in the Cloud console. It runs on separate hardware and your database can connect to it in the :ref:`usual way <connection>`.

How it Works Internally
-----------------------

Citus is an extension of PostgreSQL and can thus leverage all the features of the underlying database. Forking is actually just point-in-time recovery (PITR) into a new database where the recovery time is just the time the fork is initiated. The two features relevant for PITR are:

* Base Backups
* Write-Ahead Log (WAL) Shipping

PostgreSQL base backups are simply archives of the data directory. Any archive of the data directory is a base backup, and tools such as `pg_basebackup <https://www.postgresql.org/docs/current/static/app-pgbasebackup.html>`_ exist to automate the backups.

`Log shipping <https://www.postgresql.org/docs/current/static/continuous-archiving.html#BACKUP-ARCHIVING-WAL>`_ in PostgreSQL calls a user-provided command that takes a WAL file and stores it somewhere. This command can be a simple ``cp`` that will copy the WAL file to a disk in the network or something more capable like `WAL-E <https://github.com/wal-e/wal-e>`_.

Base backups and WAL archives are all that is needed to restore the database to some specific point in time. First we restore a base backup that was before the desired restoration time. Then we create a `recovery.conf <https://www.postgresql.org/docs/current/static/recovery-config.html>`_ file with the target time, the command to restore a requested WAL file from the archives, and other configuration options. The new PostgreSQL instances, upon entering recovery mode, will start playing WAL segments up to the target point. After the recovery instances reach the specified target, they will be available for use as a regular database.

A Citus formation is a group of PostgreSQL instances that work together. To restore the formation we simply need to restore all nodes in the cluster to the same point in time. We perform that operation on each node and, once done, we update metadata in the coordinator node to tell it that this new cluster has branched off from your original.
