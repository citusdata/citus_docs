.. _tut_sharding:
.. highlight:: bash

Sharding Data
=============

In this tutorial we'll look at a stream of live wikipedia edits. Wikimedia is
kind enough to publish all changes happening across all their sites in real time;
this can be a lot of events!

This tutorial assumes you've set up a :ref:`single-machine demo cluster <tut_cluster>`.
Once your cluster is running, open a prompt to the master instance:

::

  cd citus-tutorial
  bin/psql postgresql://:9700

This will open a new prompt. You can leave it at any time by hitting
:kbd:`Ctrl` + :kbd:`D`.

This time we're going to make two tables.

.. code-block:: sql

  CREATE TABLE wikipedia_editors (
    editor TEXT UNIQUE, -- The name of the editor
    bot BOOLEAN, -- Whether they are a bot (self-reported)

    edit_count INT, -- How many edits they've made
    added_chars INT, -- How many characters they've added
    removed_chars INT, -- How many characters they've removed

    first_seen TIMESTAMPTZ, -- The time we first saw them edit
    last_seen TIMESTAMPTZ -- The time we last saw them edit
  );

  CREATE TABLE wikipedia_changes (
    editor TEXT, -- The editor who made the change
    time TIMESTAMP WITH TIME ZONE, -- When they made it

    wiki TEXT, -- Which wiki they edited
    title TEXT, -- The name of the page they edited

    comment TEXT, -- The message they described the change with
    minor BOOLEAN, -- Whether this was a minor edit (self-reported)
    type TEXT, -- "new" if this created the page, "edit" otherwise

    old_length INT, -- how long the page used to be
    new_length INT -- how long the page is as of this edit
  );

These tables are regular Postgres tables. We need to tell Citus that they
should be distributed tables, stored across the cluster.

.. code-block:: sql

  SELECT master_create_distributed_table(
    'wikipedia_changes', 'editor', 'hash'
  );
  SELECT master_create_distributed_table(
    'wikipedia_editors', 'editor', 'hash'
  );

These say to store each table as a collection of shards, each responsible for
holding a different subset of the data. The shard a particular row belongs in
will be computed by hashing the ``editor`` column. The page on :ref:`hash_distribution`
goes into more detail.

Finally, create the shards:

.. code-block:: sql

  SELECT master_create_worker_shards('wikipedia_editors', 16, 1);
  SELECT master_create_worker_shards('wikipedia_changes', 16, 1);

This tells Citus to create 16 shards for each table, and save 1 replica of
each. You can ask Citus to store multiple copies of each shard, which allows it
to recover from worker failures without losing data or dropping queries.
However, in this example cluster we only have 1 worker, so Citus would error
out if we asked it to store any more than 1 replica.

Now we're ready to accept some data! **Open a separate terminal**
and run the data ingest script we've made for you in this new terminal:

::

  # - in a new terminal -

  cd citus-tutorial
  scripts/collect-wikipedia-user-data postgresql://:9700

This should keep running and aggregating data on the users who are
editting right now. Let's run some queries! If you run any of these
queries multiple times you'll see the results update as more data
is ingested. Returning to our existing psql terminal we can ask
some simple questions, such as finding edits which were made by
bots:

.. code-block:: sql

  -- back in the original (psql) terminal

  SELECT comment FROM wikipedia_changes c, wikipedia_editors e
  WHERE c.editor = e.editor AND e.bot IS true LIMIT 10;

Above, when we created our two tables, we partitioned them along the same
column and created an equal number of shards for each. Doing this means that
all data for each editor is kept on the same machine, or, colocated.

How many pages have been created by bots? By users?

.. code-block:: sql

  SELECT bot, count(*) as pages_created
  FROM wikipedia_changes c,
       wikipedia_editors e
  WHERE c.editor = e.editor
        AND type = 'new'
  GROUP BY bot;

Citus can also perform joins where the rows to be joined are not stored on the
same machine. But, joins involving colocated rows usually run `faster` than
their non-distributed versions, because they can run across all machines and
shards in parallel.

A surprising amount of the content in wikipedia is written by users who stop by
to make just one or two edits and don't even bother to create an account. Their
username is just their ip address, which will look something like '95.180.5.193'
or '2607:FB90:25C8:8785:0:42:36E9:7E01'.

We can (using a very rough regex), find their edits:

.. code-block:: sql

  SELECT editor SIMILAR TO '[0-9.A-F:]+' AS ip_editor,
         COUNT(1) AS edit_count,
         SUM(added_chars) AS added_chars
  FROM wikipedia_editors WHERE bot is false
  GROUP BY ip_editor;

Usually, around a fifth of all non-bot edits are made from unregistered
editors. The real percentage is a lot higher, since "bot" is a user-settable
flag which many bots neglect to set.

This script showed a data layout which many Citus users choose. One
table stored a stream of events while another table stored some
aggregations of those events and made queries over them quick.

That's all for now. To learn more about Citus continue to the
:ref:`next tutorial <tut_timeseries>`, or, if you're done with the
cluster, run this to stop the worker and master:

::

  bin/pg_ctl -D data/master stop
  bin/pg_ctl -D data/worker stop
