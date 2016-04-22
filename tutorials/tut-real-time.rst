.. _tut_real_time:
.. highlight:: bash

Real Time Aggregation
#####################

In this tutorial we'll look at a stream of live wikipedia edits. Wikimedia is
kind enough to publish all changes happening across all their sites in real time;
this can be a lot of events!

.. note::

  This tutorial assumes you've setup a Citus cluster. If you haven't, check out the
  :ref:`development` section before continuing.

  If you're using the **Docker** machine image on **Mac**::

    export DATABASE_URI=postgres://postgres@$(docker-machine ip)

  Else if you're using the **Docker** machine image on **Linux**::

    export DATABASE_URI=postgres://postgres@localhost

  Else if you're using the tutorial **tarball** (not Docker)::

    export DATABASE_URI=postgresql://:9700


Let's now get the cluster ready to accept the stream of edits. First, open a psql shell
to the master:

::

  cd try-citus
  bin/psql $DATABASE_URI

This will open a new prompt. You can leave psql at any time by hitting
:kbd:`Ctrl` + :kbd:`D`.

Create a table for the wikipedia data to be entered into:

.. code-block:: sql

  CREATE TABLE wikipedia_edits (
    time TIMESTAMP WITH TIME ZONE, -- When the edit was made

    editor TEXT, -- The editor who made the change
    bot BOOLEAN, -- Whether the editor is a bot

    wiki TEXT, --  Which wiki was edited
    namespace TEXT, -- Which namespace the page is a part of
    title TEXT, -- The name of the page

    comment TEXT, -- The message they described the change with
    minor BOOLEAN, -- Whether this was a minor edit (self-reported)
    type TEXT, -- "new" if this created the page, "edit" otherwise

    old_length INT, -- How long the page used to be
    new_length INT -- How long the page is as of this edit
  );

The ``wikipedia_edits`` table is currently a regular Postgres table. Its growth
is limited by how much data the master can hold and queries against it don't
benefit from any parallelism.

Tell Citus that it should be a distributed table:

.. code-block:: sql

  SELECT master_create_distributed_table(
    'wikipedia_edits', 'time', 'append'
  );

This says to append distribute
the ``wikipedia_edits`` table using the ``time`` column. The table will be
stored as a collection of shards, each responsible for a range of ``time``
values. The page on :ref:`append_distribution` goes into more detail.

Each shard can be on a different worker, letting the table grow to sizes too
big for any one node to handle. Queries against this table run across all
shards in parallel. Even on a single machine, this can have some significant
performance benefits!

By default, Citus will replicate each shard across multiple workers. Since we
only have one worker, we have to tell Citus that not replicating is okay:

.. code-block:: sql

  SET citus.shard_replication_factor = 1;

If we didn't do the above, when we went to create a shard Citus would give us
an error rather than accepting data it can't backup.

Now we create a shard for the data to be inserted into:

.. code-block:: sql

  SELECT master_create_empty_shard('wikipedia_edits');

Citus is eagerly awaiting data, let's give it some! **Open a separate
terminal** and set your environment variable ($DATABASE_URI) again.
Then, run the data ingest script we've made for you in this new
terminal:

::

  # - in a new terminal -
  # remember to re-export the DATABASE_URI environment variable

  cd try-citus
  scripts/insert-live-wikipedia-edits $DATABASE_URI

This should continue running and adding edits, let's run some queries
on them!  If you run any of these queries multiple times you'll see
the results update.  Data is available to be queried in Citus as
soon as it is ingested. Returning to our psql session on the master
node we can ask who the most prolific editors are:

.. code-block:: sql

  -- back in the original (psql) terminal

  SELECT count(1) AS edits, editor
  FROM wikipedia_edits
  GROUP BY 2 ORDER BY 1 DESC LIMIT 20;

This is likely to be dominated by bots, so we can look at just the sources
which represent actual users:

.. code-block:: sql

  SELECT count(1) AS edits, editor
  FROM wikipedia_edits WHERE bot IS false
  GROUP BY 2 ORDER BY 1 DESC LIMIT 20;

Unfortunately, 'bot' is a user-settable flag which many bots forget to send, so
this list is usually also dominated by bots.

Another user-settable flag is "minor", which users can hit to indicate they've
made a small change which doesn't need to be reviewed as carefully. Let's see
if they're actually following instructions:

.. code-block:: sql

  SELECT
    avg(
      CASE WHEN minor THEN abs(new_length - old_length) END
    ) AS average_minor_edit_size,
    avg(
      CASE WHEN NOT minor THEN abs(new_length - old_length) END
    ) AS average_normal_edit_size
  FROM wikipedia_edits
  WHERE old_length IS NOT NULL AND new_length IS NOT NULL;

Or how about combining the two? What are the top contributors, and how big are their edits?

.. code-block:: sql

  SELECT
    COUNT(1) AS total_edits,
    editor,
    avg(abs(new_length - old_length)) AS average_edit_size
  FROM wikipedia_edits
  WHERE new_length IS NOT NULL AND old_length IS NOT NULL
  GROUP BY 2 ORDER BY 1 DESC LIMIT 20;

That's all for now. To learn more about Citus continue to the :doc:`next
tutorial <./tut-user-data>`, or, if you're done with the cluster, run these to
stop the worker and master:

.. note::

  The procedure to stop the worker and master differs based on how
  you set up your system.

  If you used the **native** installation steps::

    bin/pg_ctl -D data/master stop
    bin/pg_ctl -D data/worker stop

  Else if you're using the **Docker** machine image::

    docker-compose -p citus down
