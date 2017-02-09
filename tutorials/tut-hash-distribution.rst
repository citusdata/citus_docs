.. _tut_hash:
.. highlight:: bash

Hash-Distributed Data
#####################

Start Demo Cluster
==================

To do the tutorial you'll need a single-machine Citus cluster with a master and worker PostgreSQL instances. Follow these instructions to create a temporary installation which is quick to try and easy to remove.

**1. Download the package**

.. raw:: html 

  <ul>
  <li> OS X Package: <a href="https://packages.citusdata.com/tutorials/citus-tutorial-osx-1.3.2.tar.gz" onclick="trackOutboundLink('https://packages.citusdata.com/tutorials/citus-tutorial-osx-1.3.2.tar.gz'); return false;">Download</a>
  </li>
  <li> Linux Package: <a href="https://packages.citusdata.com/tutorials/citus-tutorial-linux-1.3.2.tar.gz" onclick="trackOutboundLink('https://packages.citusdata.com/tutorials/citus-tutorial-linux-1.3.2.tar.gz'); return false;">Download</a>
  </li>
  </ul>

Download and unzip it into a directory of your choosing. Then, enter that directory:

::

  cd citus-tutorial

**2. Initialize the cluster**

Citus has two kinds of components, the master and the workers. The master
coordinates queries and maintains metadata on where in the cluster each row of
data is. The workers hold your data and respond to queries.

Let's create directories for those nodes to store their data in:

::

  bin/initdb -D data/master
  bin/initdb -D data/worker

The above commands will give you warnings about trust authentication. Those
will become important when you're setting up a production instance of Citus but
for now you can safely ignore them.

Citus is a Postgres extension. To tell Postgres to use this extension,
you'll need to add it to a configuration variable called
``shared_preload_libraries``:

::

  echo "shared_preload_libraries = 'citus'" >> data/master/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> data/worker/postgresql.conf

**3. Start the master and worker**

We assume that ports 9700 (for the master) and 9701 (for the worker) are
available on your machine. Feel free to use different ports if they are in use.

Let's start the databases::

  bin/pg_ctl -D data/master -o "-p 9700" -l master_logfile start
  bin/pg_ctl -D data/worker -o "-p 9701" -l worker_logfile start

And initialize them::

  bin/createdb -p 9700 $(whoami)
  bin/createdb -p 9701 $(whoami)

Above you added Citus to ``shared_preload_libraries``. That lets it hook into some
deep parts of Postgres, swapping out the query planner and executor.  Here, we
load the user-facing side of Citus (such as the functions you'll soon call):

::

  bin/psql -p 9700 -c "CREATE EXTENSION citus;"
  bin/psql -p 9701 -c "CREATE EXTENSION citus;"

Finally, the master needs to know where it can find the worker. To tell it you can run:

::

  bin/psql -p 9700 -c "SELECT * from master_add_node('localhost', 9701);"

Ingest Data
===========

In this tutorial we'll look at a stream of live wikipedia edits. Wikimedia is
kind enough to publish all changes happening across all their sites in real time;
this can be a lot of events!

Now that your cluster is running, open a prompt to the master instance:

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

  SELECT create_distributed_table('wikipedia_changes', 'editor');
  SELECT create_distributed_table('wikipedia_editors', 'editor');

These say to store each table as a collection of shards, each
responsible for holding a different subset of the data. The shard
a particular row belongs in will be computed by hashing the ``editor``
column. The page on :ref:`ddl` goes into more detail.

In addition, these UDF's create citus.shard_count shards for each table, and save one
replica of each shard. You can ask Citus to store multiple copies of each shard, which
allows it to recover from worker failures without losing data or dropping queries.
However, in this example cluster we only have 1 worker, so Citus would error
out if we asked it to store any more than 1 replica.

Now we're ready to accept some data! **Open a separate terminal**
and run the data ingest script we've made for you in this new terminal:

::

  # - in a new terminal -

  cd citus-tutorial
  scripts/collect-wikipedia-user-data postgresql://:9700

This should keep running and aggregating data on the users who are
editting right now.

Run Queries
===========

Let's run some queries! If you run any of these
queries multiple times you'll see the results update as more data
is ingested. Returning to our existing psql terminal we can ask
some simple questions, such as finding edits which were made by
bots:

.. code-block:: sql

  -- back in the original (psql) terminal

  SELECT comment FROM wikipedia_changes c, wikipedia_editors e
  WHERE c.editor = e.editor AND e.bot IS true LIMIT 10;

Above, when we created our two tables, we partitioned them along the
same column and created an equal number of shards for each. Doing this
means that all data for each editor is kept on the same machine, or,
:ref:`co-located <colocation>`.

How many pages have been created by bots? By users?

.. code-block:: sql

  SELECT bot, count(*) as pages_created
  FROM wikipedia_changes c,
       wikipedia_editors e
  WHERE c.editor = e.editor
        AND type = 'new'
  GROUP BY bot;

Citus can also perform joins where the rows to be joined are not stored on the
same machine. But, joins involving co-located rows usually run `faster` than
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

We hope you enjoyed working through this tutorial. Once you're ready
to stop the cluster run these commands:

::

  bin/pg_ctl -D data/master stop
  bin/pg_ctl -D data/worker stop

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'hash', section: 'tutorial'});
  </script>
