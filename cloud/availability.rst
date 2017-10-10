.. _ha:

Availability and Recovery
#########################

High-Availability
=================

Citus Cloud continuously protects the cluster data against hardware
failure. To do this we perform backups every twenty-four hours, then
stream the write-ahead log (WAL) from PostgreSQL to S3 every 16 MB or 60
seconds, whichever is less. Even without high availability enabled you
won't lose any data. In the event of a complete infrastructure failure
we'll restore your back-up and replay the WAL to the exact moment before
your system crashed.

In addition to continuous protection which is explained above, high
availability is available if your application requires less exposure
to downtime. We provision stand-bys if you select high availability
at provisioning time. This can be for your primary node, or for your
distributed nodes.

Let's examine these concepts in greater detail.

Introduction to High Availability and Disaster Recovery
-------------------------------------------------------

In the real world, insurance is used to manage risk when a natural
disaster such as a hurricane or flood strikes. In the database world,
there are two critical methods of insurance. High Availability (HA)
replicates the latest database version virtually instantly. Disaster
Recovery (DR) offers continuous protection by saving every database
change, allowing database restoration to any point in time.

In what follows, we’ll dig deeper as to what disaster recovery and high
availability are, as well as how we’ve implemented them for Citus Cloud.

What is High Availability and Disaster Recovery?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

High availability and disaster recovery are both forms of data backups
that are mutually exclusive and inter-related. The difference between
them, is that HA has a secondary reader database replica (often referred
to as stand-by or follower) ready to take over at any moment, but DR
just writes to cold storage (in the case of Amazon that’s S3) and has
latency in the time for the main database to recover data.

Overview of High Availability
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. image:: ../images/ha-availability.gif
   :align: right

For HA, any data that is written to a primary database called the Writer
is instantly replicated onto a secondary database called the Reader in
real-time, through a stream called a
`WAL <https://www.postgresql.org/docs/9.4/static/wal-intro.html>`__ or
Write-Ahead-Log.

To ensure HA is functioning properly, Citus Cloud runs health checks
every 30 seconds. If the primary fails and data can’t be accessed after
six consecutive attempts, a failover is initiated. This means the
primary node will be replaced by the standby node and a new standby will
be created.

Overview of Disaster Recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. image:: ../images/ha-disaster.gif
   :align: right

For DR, read-only data is replayed from colder storage. On AWS this is
from S3, and for Postgres this is downloaded in 16 MB pieces. On Citus
Cloud this happens via WAL-E, using precisely the same procedure as
creating a new standby for HA.
`WAL-E <https://github.com/wal-e/wal-e>`__ is an open source tool
initially developed by our team, for archiving PostgreSQL WAL (Write
Ahead Log) files quickly, continuously and with a low operational
burden.

This means we can restore your database by fetching the base backup and
replaying all of the WAL files on a fresh install in the event of
hardware failure, data corruption or other failure modes

On Citus Cloud prior to kicking off the DR recovery process, the AWS EC2
instance is automatically restarted. This process usually takes 7±2
minutes. If it restarts without any issues, the setup remains the same.
If the EC2 instance fails to restart, a new instance is created. This
happens at a rate of at least 30MB/second, so 512GB of data would take
around 5 hours.

How High Availability and Disaster Recovery fit together
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

While some may be familiar many are not acutely aware of the
relationship between HA and DR.

Although it’s technically possible to have one without the other, they
are unified in that the HA streaming replication and DR archiving
transmit the same bytes.

For HA the primary “writer” database replicates data through streaming
replication to the secondary “reader” database. For DR, the same data is
read from S3. In both cases, the “reader” database downloads the WAL and
applies it incrementally.

Since DR and HA gets regularly used for upgrades and side-grades, the DR
system is maintained with care. We ourselves rely on it for releasing
new production features.

Disaster Recovery takes a little extra work but gives greater reliability
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You might think that if HA provides virtually instant backup
reliability, so ‘Why bother with DR?’ There are some compelling reasons
to use DR in conjunction with HA including cost, reliability and
control.

From a cost efficiency perspective, since HA based on EBS and EC2 is a
mirrored database, you have to pay for every layer of redundancy added.
However, DR archives in S3 are often 10-30% of the monthly cost of a
database instance. And with Citus Cloud the S3 cost is already covered
for you in the standard price of your cluster.

From reliability perspective, S3 has proven to be up to a thousand times
more reliable than EBS and EC2, though a more reasonable range is ten to
a hundred times. S3 archives also have the advantage of immediate
restoration, even while teams try to figure out what’s going on.
Conversely, sometimes EBS volume availability can be down for hours with
uncertainty it will completely restore.

From a control perspective, using DR means a standby database can be
created while reducing the impact on the primary database. It also has
the capability of being able to recover a database from a previous
version.

Trade-offs between latency and reliability
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There is a long history of trade-offs between latency and reliability,
dating back to when the gold standard for backups were on spools of
tape.

Writing data to and then reading data from S3 offers latencies that are
100 to 1,000 times longer than streaming bytes between two computers as
seen in streaming replication. However, S3's availability and durability
are both in excess of ten times better than an EBS volume.

On the other hand, the throughput of S3 is excellent: with parallelism,
and without downstream bottlenecks, one can achieve multi-gigabit
throughput in backup and WAL reading and writing.

How High Availability and Disaster Recovery is used for crash recovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When many customers entrust your company with their data, it is your
duty to keep it safe under all circumstances. So when the most severe
database crashes strike, you need to be ready to recover.

Our team is battle-hardened from years of experience as the original
Heroku Postgres team, managing over 1.5 million databases. Running at
that scale with constant risks of failure, meant that it was important
to automate recovery processes.

Such crashes are a nightmare. But crash recovery is a way to make sure
you sleep well at night by making sure none of your or your customers
data is lost and your downtime is minimal.

.. _cloud_forking:

Forking
=======

Forking a Citus Cloud formation makes a copy of the cluster's data at an instant in time and produces a new formation in precisely that state. It allows you to change, query, or generally experiment with production data in a separate protected environment. Fork creation runs quickly, and you can do it as often as you want without causing any extra load on the original cluster. This is because forking doesn't query the cluster, rather it taps into the write-ahead logs for each database in the formation.

How to Fork a Formation
-----------------------

Citus Cloud makes forking easy. The control panel for each formation has a "Fork" tab. Go there and enter the name, region, and node sizing information for the destination cluster.

.. image:: ../images/cloud-fork.png

Shortly after you click "Fork Formation," the new formation will appear in the Cloud console. It runs on separate hardware and your database can connect to it in the :ref:`usual way <connection>`.

When is it Useful
-----------------

A fork is a great place to do experiments. Do you think that denormalizing a table might speed things up? What about creating a roll-up table for a dashboard? How can you persuade your manager that you need more RAM in the coordinator node rather than in the workers? You could prove yourself if only you could try your idea on the production data.

In such cases, what you need is a temporary copy of the production database. But it would take forever to copy, say, 500GB of data to a new formation. Not to mention that making the copy would slow down the production database. Copying the database in the old fashioned way is not a good idea.

However a Citus fork is different. Forking fetches write-ahead log data from S3 and has zero effect on the production load. You can apply your experiments to the fork and destroy it when you're done.

Another use of forking is to enable complex analytical queries. Sometimes data analysts want to have access to live production data for complex queries that would take hours. What's more, they sometimes want to bend the data: denormalize tables, create aggregations, create an extra index or even pull all the data onto one machine.

Obviously, it is not a good idea to let anyone play with a production database. You can instead create a fork and give it to whomever wants to play with real data. You can re-create a fork every month to update your analytics results.

How it Works Internally
-----------------------

Citus is an extension of PostgreSQL and can thus leverage all the features of the underlying database. Forking is actually a special form of point-in-time recovery (PITR) into a new database where the recovery time is the time the fork is initiated. The two features relevant for PITR are:

* Base Backups
* Write-Ahead Log (WAL) Shipping

About every twenty-four hours Cloud calls `pg_basebackup <https://www.postgresql.org/docs/current/static/app-pgbasebackup.html>`_ to make a new base backup, which is just an archive of the PostgreSQL data directory. Cloud also continuously ships the database write-ahead logs (WAL) to Amazon S3 with `WAL-E <https://github.com/wal-e/wal-e>`_.

Base backups and WAL archives are all that is needed to restore the database to some specific point in time. To do so, we start an instance of the database on the base backup taken most recently before the desired restoration point. The new PostgreSQL instances, upon entering recovery mode, will start playing WAL segments up to the target point. After the recovery instances reach the specified target, they will be available for use as a regular database.

A Citus formation is a group of PostgreSQL instances that work together. To restore the formation we simply need to restore all nodes in the cluster to the same point in time. We perform that operation on each node and, once done, we update metadata in the coordinator node to tell it that this new cluster has branched off from your original.

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'Availability', section: 'cloud'});
  </script>
