.. highlight:: bash

.. _single_node_linux:

Linux
=======================================================

This section will show you how to create a working installation of Citus.

**1. Download the package**

We've provided `a tarball
<https://s3.amazonaws.com/packages.citusdata.com/tutorials/try-citus-4.tar.gz>`_
which lets you configure and start Citus without requiring sudo.

Download and unzip it into a directory of your choosing. Then, enter that directory:

::

  cd try-citus

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

**4. Go run some queries**

Your cluster is running and eagerly waiting for data. We created tutorials for you that
show example use-cases. :ref:`Visit our tutorials to feed data into your Citus cluster and
run example queries within minutes <tut_real_time>`.
