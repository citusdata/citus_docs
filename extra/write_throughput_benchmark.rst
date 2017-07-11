:orphan:

.. _citus_write_throughput_benchmark:

Benchmark Setup with Citus and pgbench
--------------------------------------

In this section, we provide step by step instructions to benchmark Citus' write throughput. For these benchmark steps, we use `Citus Cloud <https://console.citusdata.com/users/sign_up>`_ to create test clusters, and a standard benchmarking tool called `pgbench  <https://www.postgresql.org/docs/current/static/pgbench.html>`_ to run write throughput tests.

If you're interested in general throughput numbers based on these tests, you can also find them in our :ref:`_scaling_data_ingestion`.

Create Citus Cluster
~~~~~~~~~~~~~~~~~~~~

The easiest way to start a Citus Cluster is by vising the Citus Cloud dashboard. This dashboard allows you to choose different coordinator and worker node configurations and bills you by the hour. Once you picked your desired cluster setup, click on the "Create New Formation" button.


A pop-up will ask you the AWS region (US East, US West) where your formation will be created. Please remember the region where you created your Citus Cloud formation. We will use it in the next step.

If you're planning to run the following steps on your own cluster, please note that Citus Cloud automatically tunes your cluster based on the hardware configuration. For this benchmark, you will need to manully increase `max_connections = 303` across the coordinator and worker nodes.

Create an Instance to Run pgbench
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pgbench is standard utility provided by PostgreSQL to perform benchmarks. pgbench runs given SQL commands repeatedly and measures number of completed transactions per second.

Since pgbench itself uses some CPU power to execute SQL commands repeatedly, we recommend that you run pgbench on a separate machine than the one where the Citus cluster runs. This recommendation also follows pgbench's own documentation.

Therefore, we're going to create a separate EC2 instance to run pgbench, and place the instance in the same EC2 region as our Citus cluster. We will also use a large EC2 (m4.16xlarge) instance to ensure pgbench itself doesn't become the bottleneck.

Install pgbench
~~~~~~~~~~~~~~~

Once we create a new EC2 instance, we need to install pgbench on this instance.

If you are running a **Debian** based system, please type::

  sudo apt-get update
  sudo apt-get install postgresql-contrib-9.5

If you are running a **RedHat** based system, please type::

  sudo yum update
  sudo yum install postgresql95-contrib


Benchmark INSERT Throughput
---------------------------

Initialize and Distribute Tables
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Before we start, we need to tell pgbench to initialize the benchmarking environment by creating test tables. Then, we need to connect to the Citus coordinator node and distribute the table that we're going to run INSERT tests on.

To initialize the test environment and distribute the related table, we need to get a connection string to the cluster. You can get this connection string from your Citus Cloud dashboard. Then, you need to run the following commands::

  pgbench -i connection_string_to_coordinator
  psql connection_string_to_coordinator
  
  psql=> SELECT create_distributed_table('pgbench_history', 'aid');


Prepare SQL File to Run with pgbench
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pgbench runs the given SQL commands repeatedly and reports results. For this benchmark run, we will use the INSERT command that comes with the pgbench benchmark.

To create the related SQL commands, create a file named insert.sql and pase the following lines into it::

  \set nbranches :scale
  \set ntellers 10 * :scale
  \set naccounts 100000 * :scale
  \setrandom aid 1 :naccounts
  \setrandom bid 1 :nbranches
  \setrandom tid 1 :ntellers
  \setrandom delta -5000 5000
  INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);


Benchmark INSERT commands
~~~~~~~~~~~~~~~~~~~~~~~~~

By default, pgbench opens a single connection to the database and sends INSERT commands through this connection. To benchmark write throughput, we're going to open parallel connections to the database and issue concurrent commands. In particular, we're going to use pgbench's -j parameter to specify the number of concurrent threads and -c parameter to specify the number of concurrent connections. We will also set the duration for our tests to 30 seconds using the -T parameter.

To run pgbench with these parameters, simply type::

  pgbench connection_string_to_coordinator -j 64 -c 256 -f insert.sql -T 30

Please note that these parameters open 256 concurrent connections to Citus. If you're running Citus on your own instances, you will need to increase the default max_connections setting.

.. _citus_update_throughput_benchmark:

Benchmark UPDATE Throughput
---------------------------

Initialize and Distribute Tables
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Before we start, we need to tell pgbench to initialize the benchmarking environment by creating test tables. Then, we need to connect to the Citus coordinator node and distribute the table that we're going to run UPDATE tests on.

To initialize the test environment and distribute the related table, we need to get a connection string to the cluster. You can get this connection string from your Citus Cloud dashboard. Then, you need to run the following commands::

  pgbench -i connection_string_to_coordinator
  psql connection_string_to_coordinator
  
  psql=> /* INSERT and UPDATE tests run on different distributed tables */
  psql=> SELECT create_distributed_table('pgbench_accounts', 'aid');


Prepare SQL File to Run with pgbench
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

pgbench runs the given SQL commands repeatedly and reports results. For this benchmark run, we will use the INSERT command that comes with the pgbench benchmark.

To create the related SQL commands, create a file named update.sql and pase the following lines into it::

  \set naccounts 100000 * :scale
  \setrandom aid 1 :naccounts
  \setrandom delta -5000 5000
  UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;


Benchmark UPDATE commands
~~~~~~~~~~~~~~~~~~~~~~~~~

By default, pgbench opens a single connection to the database and sends INSERT commands through this connection. To benchmark write throughput, we're going to open parallel connections to the database and issue concurrent commands. In particular, we're going to use pgbench's -j parameter to specify the number of concurrent threads and -c parameter to specify the number of concurrent connections. We will also set the duration for our tests to 30 seconds using the -T parameter.

To run pgbench with these parameters, simply type::

  pgbench connection_string_to_coordinator -j 64 -c 256 -f update.sql -T 30

Please note that these parameters open 256 concurrent connections to Citus. If you're running Citus on your own instances, you will need to increase the default max_connections setting.
