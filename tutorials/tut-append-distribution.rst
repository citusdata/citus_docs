.. _tut_timeseries:
.. highlight:: bash

Working with Timeseries
#######################

In this tutorial we'll continue looking at wikipedia edits. The previous
tutorial ingested a stream of all live edits happening across wikimedia.  We'll
continue looking at that stream but store it in a different way.

This tutorial assumes you've set up a :ref:`single-machine demo cluster <tut_cluster>`.
Our first task is to get the cluster ready to accept a stream of wikipedia edits.
First, open a psql shell to the master:

::

  cd citus-tutorial
  bin/psql postgresql://:9700

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
terminal** and run the data ingest script we've made for you.
::

  # - in a new terminal -

  cd citus-tutorial
  scripts/insert-live-wikipedia-edits postgresql://:9700

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

We hope you enjoyed working through our tutorials. Once you're ready to stop
the cluster run these commands:

::

  bin/pg_ctl -D data/master stop
  bin/pg_ctl -D data/worker stop
