.. _tut_cluster:
.. highlight:: bash

Start Demo Cluster
##################

To do the tutorials you'll need a single-machine Citus cluster with a master and two worker PostgreSQL instances. Follow these instructions to create a temporary installation which is quick to try and easy to remove.

**1. Download the package**

.. raw:: html 

  <ul>
  <li> OS X Package: <a href="https://packages.citusdata.com/tutorials/citus-tutorial-osx-1.1.0.tar.gz" onclick="trackOutboundLink('https://packages.citusdata.com/tutorials/citus-tutorial-osx-1.1.0.tar.gz'); return false;">Download</a>
  </li>
  <li> Linux Package: <a href="https://packages.citusdata.com/tutorials/citus-tutorial-linux-1.1.0.tar.gz" onclick="trackOutboundLink('https://packages.citusdata.com/tutorials/citus-tutorial-linux-1.1.0.tar.gz'); return false;">Download</a>
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

The master needs to know where it can find the worker. To tell it you can run:

::

  echo "localhost 9701" >> data/master/pg_worker_list.conf

We assume that ports 9700 (for the master) and 9701 (for the worker) are
available on your machine. Feel free to use different ports if they are in use.

Citus is a Postgres extension. To tell Postgres to use this extension,
you'll need to add it to a configuration variable called
``shared_preload_libraries``:

::

  echo "shared_preload_libraries = 'citus'" >> data/master/postgresql.conf
  echo "shared_preload_libraries = 'citus'" >> data/worker/postgresql.conf

**3. Start the master and worker**

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

**4. Ready for the tutorials!**

Your cluster is running and eagerly awaiting data. Proceed to the 
:ref:`Real Time Aggregation <tut_timeseries>` tutorial to begin learning
how to use Citus.
