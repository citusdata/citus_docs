Timeseries Data
===============

In a time-series workload, applications (such as some :ref:`distributing_by_entity_id`) query recent information, while archiving old information.

To deal with this workload, a single-node PostgreSQL database would typically use `table partitioning <https://www.postgresql.org/docs/current/static/ddl-partitioning.html>`_ to break a big table of time-ordered data into multiple inherited tables with each containing different time ranges.

Storing data in multiple physical tables speeds up data expiration. In a single big table, deleting rows incurs the cost of scanning to find which to delete, and then `vacuuming <https://www.postgresql.org/docs/10/static/routine-vacuuming.html>`_ the emptied space. On the other hand, dropping a partition is a fast operation independent of data size. It's the equivalent of simply removing files on disk that contain the data.

.. image:: ../images/timeseries-delete-vs-drop.png

Partitioning a table also makes indices smaller and faster within each date range. Queries operating on recent data are likely to operate on "hot" indices that fit in memory. This speeds up reads.

.. image:: ../images/timeseries-multiple-indices-select.png

Also inserts have smaller indices to update, so they go faster too.

.. image:: ../images/timeseries-multiple-indices-insert.png

Time-based partitioning makes most sense when:

1. Most queries access a very small subset of the most recent data
2. Older data is periodically expired (deleted/dropped)

Keep in mind that, in the wrong situation, reading all these partitions can hurt overhead more than it helps. However in the right situations it is quite helpful. For example, when keeping a year of time series data and regularly querying only the most recent week.

Scaling Timeseries Data on Citus
--------------------------------

We can mix the single-node table partitioning techniques with Citus' distributed sharding to make a scalable time-series database. It's the best of both worlds. It's especially elegant atop the declarative table partitioning in Postgres 10.

.. image:: ../images/timeseries-sharding-and-partitioning.png

For example, let's distribute *and* partition a table holding historical `GitHub events data <https://examples.citusdata.com/events.csv>`__.

Each record in this GitHub data set represents an event created in GitHub, along with key information regarding the event such as event type, creation date, and the user who created the event.

The first step is to create and partition the table by time as we would in a single-node PostgreSQL database:

.. code-block:: postgresql

  -- the separate schema will be useful later
  CREATE SCHEMA github;

  -- declaratively partitioned table
  CREATE TABLE github.events (
    event_id bigint,
    event_type text,
    event_public boolean,
    repo_id bigint,
    payload jsonb,
    repo jsonb, actor jsonb,
    org jsonb,
    created_at timestamp
  ) PARTITION BY RANGE (created_at);

Notice the ``PARTITION BY RANGE (created_at)``. This tells Postgres that the table will be partitioned by the ``created_at`` column in ordered ranges. We have not yet created any partitions for specific ranges, though.

Before creating specific partitions, let's distribute the table in Citus. We'll shard by ``repo_id``, meaning the events will be clustered into shards per repository.

.. code-block:: postgresql

  SELECT create_distributed_table('github.events', 'repo_id');

At this point Citus has created shards for this table across worker nodes. Internally each shard is a table with the name ``github.events_N`` for each shard identifier N. Also, Citus propagated the partitioning information, and each of these shards has ``Partition key: RANGE (created_at)`` declared.

A partitioned table cannot directly contain data, it is more like a view across its partitions. Thus the shards are not yet ready to hold data. We need to manually create partitions and specify their time ranges, after which we can insert data that match the ranges.

.. code-block:: postgresql

  -- manually make a partition for 2016 events
  CREATE TABLE github.events_2016 PARTITION OF github.events
  FOR VALUES FROM ('2016-01-01') TO ('2016-12-31');

The coordinator node now has the tables ``github.events`` and ``github.events_2016``. Citus will propagate partition creation to all the shards, creating a partition for each shard.

Automating Partition Creation
-----------------------------

In the previous section we manually created a partition of the ``github.events`` table. It's tedious to keep doing this, especially when using narrower partitions holding less than a year's range of data. It's more pleasant to let the `pg_partman extension <https://github.com/keithf4/pg_partman>`_ automatically create partitions on demand. The core functionality of pg_partman works out of the box with Citus when using it with native partitioning.

First clone, build, and install the pg_partman extension. Then tell partman we want to make partitions that each hold one hour of data. This will create the initial empty hourly partitions:

.. code-block:: sql

  CREATE SCHEMA partman;
  CREATE EXTENSION pg_partman WITH SCHEMA partman;

  -- Partition the table into hourly ranges of "created_at"
  SELECT partman.create_parent('github.events', 'created_at', 'native', 'hourly');
  UPDATE partman.part_config SET infinite_time_partitions = true;

  -- running "\d+ github.events" will now show more partitions

By default ``create_parent`` creates four partitions in the past, four in the future, and one for the present, all based on system time. If you need to backfill older data, you can specify a ``p_start_partition`` parameter in the call to ``create_parent``, or ``p_premake`` to make partitions for the future. See the `pg_partman documentation <https://github.com/keithf4/pg_partman/blob/master/doc/pg_partman.md>`_ for details.

As time progresses, pg_partman will need to do some maintenance to create new partitions and drop old ones. Anytime you want to trigger maintenance, call:

.. code-block:: postgresql

  -- disabling analyze is recommended for native partitioning
  -- due to aggressive locks
  SELECT run_maintenance(p_analyze := false);

It's best to set up a periodic job to run the maintenance function. Pg_partman can be built with support for a background worker (BGW) process to do this. Or we can use another extension like `pg_cron <https://github.com/citusdata/pg_cron>`_:

.. code-block:: postgresql

  SELECT cron.schedule('@hourly', $$
    SELECT partman.run_maintenance(p_analyze := false);
  $$);

Once periodic maintenance is set up, you no longer have to think about the partitions, they just work.

Finally, to configure pg_partman to drop old partitions, you can update the ``partman.part_config`` table:

.. code-block:: postgresql

  UPDATE partman.part_config
     SET retention_keep_table = false,
         retention = '1 month'
   WHERE parent_table = 'github.events';

Now whenever maintenance runs, partitions older than a month are automatically dropped.

.. note::

  Be aware that native partitioning in Postgres is still quite new and has a few quirks. For example, you cannot directly create an in index on a partitioned table. Instead, pg_partman lets you create a template table to define indexes for new partitions. Maintenance operations on partitioned tables will also acquire aggressive locks that can briefly stall queries. There is currently a lot of work going on within the postgres community to resolve these issues, so expect time partitioning in Postgres to only get better.
