Table Management
$$$$$$$$$$$$$$$$$$

.. _table_size:

Determining Table and Relation Size
###################################

The usual way to find table sizes in PostgreSQL, :code:`pg_total_relation_size`, drastically under-reports the size of distributed tables. All this function does on a Citus cluster is reveal the size of tables on the coordinator node. In reality the data in distributed tables lives on the worker nodes (in shards), not on the coordinator. A true measure of distributed table size is obtained as a sum of shard sizes. Citus provides helper functions to query this information.

+------------------------------------------+---------------------------------------------------------------+
| UDF                                      | Returns                                                       |
+==========================================+===============================================================+
| citus_relation_size(relation_name)       | * Size of actual data in table (the "`main fork <forks_>`_"). |
|                                          |                                                               |
|                                          | * A relation can be the name of a table or an index.          |
+------------------------------------------+---------------------------------------------------------------+
| citus_table_size(relation_name)          | * citus_relation_size plus:                                   |
|                                          |                                                               |
|                                          |    * size of `free space map <freemap_>`_                     |
|                                          |    * size of `visibility map <vismap_>`_                      |
+------------------------------------------+---------------------------------------------------------------+
| citus_total_relation_size(relation_name) | * citus_table_size plus:                                      |
|                                          |                                                               |
|                                          |    * size of indices                                          |
+------------------------------------------+---------------------------------------------------------------+

These functions are analogous to three of the standard PostgreSQL `object size functions <https://www.postgresql.org/docs/current/static/functions-admin.html#FUNCTIONS-ADMIN-DBSIZE>`_, with the additional note that

* They work only when :code:`citus.shard_replication_factor` = 1.
* If they can't connect to a node, they error out.

Here is an example of using one of the helper functions to list the sizes of all distributed tables:

.. code-block:: postgresql

  SELECT logicalrelid AS name,
         pg_size_pretty(citus_table_size(logicalrelid)) AS size
    FROM pg_dist_partition;

Output:

::

  ┌───────────────┬───────┐
  │     name      │ size  │
  ├───────────────┼───────┤
  │ github_users  │ 39 MB │
  │ github_events │ 37 MB │
  └───────────────┴───────┘

Vacuuming Distributed Tables
############################

In PostgreSQL (and other MVCC databases), an UPDATE or DELETE of a row does not immediately remove the old version of the row. The accumulation of outdated rows is called bloat and must be cleaned to avoid decreased query performance and unbounded growth of disk space requirements. PostgreSQL runs a process called the auto-vacuum daemon that periodically vacuums (aka removes) outdated rows.

It’s not just user queries which scale in a distributed database, vacuuming does too. In PostgreSQL big busy tables have great potential to bloat, both from lower sensitivity to PostgreSQL's vacuum scale factor parameter, and generally because of the extent of their row churn. Splitting a table into distributed shards means both that individual shards are smaller tables and that auto-vacuum workers can parallelize over different parts of the table on different machines. Ordinarily auto-vacuum can only run one worker per table.

Due to the above, auto-vacuum operations on a Citus cluster are probably good enough for most cases. However for tables with particular workloads, or companies with certain "safe" hours to schedule a vacuum, it might make more sense to manually vacuum a table rather than leaving all the work to auto-vacuum.

To vacuum a table, simply run this on the coordinator node:

.. code-block:: postgresql

  VACUUM my_distributed_table;

Using vacuum against a distributed table will send a vacuum command to every one of that table's placements (one connection per placement). This is done in parallel. All `options <https://www.postgresql.org/docs/current/static/sql-vacuum.html>`_ are supported (including the :code:`column_list` parameter) except for :code:`VERBOSE`. The vacuum command also runs on the coordinator, and does so before any workers nodes are notified. Note that unqualified vacuum commands (i.e. those without a table specified) do not propagate to worker nodes.

Analyzing Distributed Tables
############################

PostgreSQL's ANALYZE command collects statistics about the contents of tables in the database. Subsequently, the query planner uses these statistics to help determine the most efficient execution plans for queries.

The auto-vacuum daemon, discussed in the previous section, will automatically issue ANALYZE commands whenever the content of a table has changed sufficiently. The daemon schedules ANALYZE strictly as a function of the number of rows inserted or updated; it has no knowledge of whether that will lead to meaningful statistical changes. Administrators might prefer to manually schedule ANALYZE operations instead, to coincide with statistically meaningful table changes.

To analyze a table, run this on the coordinator node:

.. code-block:: postgresql

  ANALYZE my_distributed_table;

Citus propagates the ANALYZE command to all worker node placements.

.. _freemap: https://www.postgresql.org/docs/current/static/storage-fsm.html
.. _vismap: https://www.postgresql.org/docs/current/static/storage-vm.html
.. _forks: https://www.postgresql.org/docs/current/static/storage-file-layout.html

Streaming Data Ingestion
########################

Ingesting Data from Kafka
=========================

Citus can leverage existing Postgres data ingestion tools. For instance, we can use a tool called `kafka-sink-pg-json <https://github.com/justonedb/kafka-sink-pg-json>`_ to copy JSON messages from a Kafka topic into a database table. As a demonstration, we'll create a ``kafka_test`` table and ingest data from the ``test`` topic with a custom mapping of JSON keys to table columns.

The easiest way to experiment with Kafka is using the `Confluent platform <https://www.confluent.io/product/confluent-platform/>`_, which includes Kafka, Zookeeper, and associated tools whose versions are verified to work together.

.. code-block:: bash

  # we're using Confluent 2.0 for kafka-sink-pg-json support
  curl -L http://packages.confluent.io/archive/2.0/confluent-2.0.0-2.11.7.tar.gz \
    | tar zx

  # Now get the jar and conf files for kafka-sink-pg-json
  mkdir sink
  curl -L https://github.com/justonedb/kafka-sink-pg-json/releases/download/v1.0.2/justone-jafka-sink-pg-json-1.0.zip -o sink.zip
  unzip -d sink $_ && rm $_

The download of kafka-sink-pg-json contains some configuration files. We want to connect to the coordinator Citus node, so we must edit the configuration file ``sink/justone-kafka-sink-pg-json-connector.properties``:

.. code-block:: sh

  # add to sink/justone-kafka-sink-pg-json-connector.properties

  # the kafka topic we will use
  topics=test

  # db connection info
  # use your own settings here
  db.host=localhost:5432
  db.database=postgres
  db.username=postgres
  db.password=bar

  # the schema and table we will use
  db.schema=public
  db.table=kafka_test

  # the JSON keys, and columns to store them
  db.json.parse=/@a,/@b
  db.columns=a,b

Notice ``db.columns`` and ``db.json.parse``. The elements of these lists match up, with the items in ``db.json.parse`` specifying where to find values inside incoming JSON objects.

.. note::

  The paths in ``db.json.parse`` are written in a language that allows some flexibility in getting values out of JSON. Given the following JSON,

  .. code-block:: json

    {
      "identity":71293145,
      "location": {
        "latitude":51.5009449,
        "longitude":-2.4773414
      },
      "acceleration":[0.01,0.0,0.0]
    }

  here are some example paths and what they match:

  * ``/@identity`` - the path to element 71293145.
  * ``/@location/@longitude`` - the path to element -2.4773414.
  * ``/@acceleration/#0`` - the path to element 0.01
  * ``/@location`` - the path to element ``{"latitude":51.5009449, "longitude":-2.4773414}``

Our own scenario is simple. Our events will be objects like ``{"a":1, "b":2}``. The parser will pull those values into eponymous columns.

Now that the configuration file is set up, it's time to prepare the database. Connect to the coordinator node with psql and run this:

.. code-block:: psql

  -- create metadata tables for kafka-sink-pg-json
  \i sink/install-justone-kafka-sink-pg-1.0.sql

  -- create and distribute target ingestion table
  create table kafka_test ( a int, b int );
  select create_distributed_table('kafka_test', 'a');

Start the Kafka machinery:

.. code-block:: bash

  # save some typing
  export C=confluent-2.0.0

  # start zookeeper
  $C/bin/zookeeper-server-start \
    $C/etc/kafka/zookeeper.properties

  # start kafka server
  $C/bin/kafka-server-start \
    $C/etc/kafka/server.properties

  # create the topic we'll be reading/writing
  $C/bin/kafka-topics --create --zookeeper localhost:2181   \
                      --replication-factor 1 --partitions 1 \
                      --topic test

Run the ingestion program:

.. code-block:: bash

  # the jar files for this are in "sink"
  export CLASSPATH=$PWD/sink/*

  # Watch for new events in topic and insert them
  $C/bin/connect-standalone \
    sink/justone-kafka-sink-pg-json-standalone.properties \
    sink/justone-kafka-sink-pg-json-connector.properties

At this point Kafka-Connect is watching the ``test`` topic, and will parse events there and insert them into ``kafka_test``. Let's send an event from the command line.

.. code-block:: bash

  echo '{"a":42,"b":12}' | \
    $C/bin/kafka-console-producer --broker-list localhost:9092 --topic test

After a small delay the new row will show up in the database.

::

  select * from kafka_test;

  ┌────┬────┐
  │ a  │ b  │
  ├────┼────┤
  │ 42 │ 12 │
  └────┴────┘

Caveats
-------

* At the time of this writing, kafka-sink-pg-json requires Kafka version 0.9 or earlier.
* The kafka-sink-pg-json connector config file does not provide a way to connect with SSL support, so this tool will not work with Citus Cloud which requires secure connections.
* A malformed JSON string in the Kafka topic will cause the tool to become stuck. Manual intervention in the topic is required to process more events.

Ingesting Data from Spark
=========================

People sometimes use Spark to transform Kafka data, such as by adding computed values. In this section we'll see how to ingest Spark dataframes into a distributed Citus table.

First let's start a local Spark cluster. It has several moving parts, so the easiest way is to run the pieces with docker-compose.

.. code-block:: bash

  wget https://raw.githubusercontent.com/gettyimages/docker-spark/master/docker-compose.yml

  # this may require "sudo" depending on the docker daemon configuration
  docker-compose up

To do the ingestion into PostgreSQL, we'll be writing custom Scala code. We'll use the Scala Build Tool (SBT) to load dependencies and run our code, so `download SBT <https://www.scala-sbt.org/download.html>`_ and install it on your machine.

Next create a new directory for our project.

.. code-block:: bash

  mkdir sparkcitus

Create a file called ``sparkcitus/build.sbt`` to tell SBT our project configuration, and add this:

.. code-block:: scala

  // add this to build.sbt

  name := "sparkcitus"
  version := "1.0"

  scalaVersion := "2.10.4"

  resolvers ++= Seq(
    "Maven Central" at "http://central.maven.org/maven2/"
  )

  libraryDependencies ++= Seq(
    "org.apache.spark" %% "spark-core" % "2.2.1",
    "org.apache.spark" %% "spark-sql"  % "2.2.1",
    "org.postgresql"   %  "postgresql" % "42.2.2"
  )

Next create a helper Scala class for doing ingestion through JDBC. Add the following to ``sparkcitus/copy.scala``:

.. code-block:: scala

  import java.io.InputStream
  import java.sql.DriverManager
  import java.util.Properties

  import org.apache.spark.sql.{DataFrame, Row}
  import org.postgresql.copy.CopyManager
  import org.postgresql.core.BaseConnection

  object CopyHelper {

    def rowsToInputStream(rows: Iterator[Row]): InputStream = {
      val bytes: Iterator[Byte] = rows.map { row =>
        (row.toSeq
          .map { v =>
            if (v == null) {
              """\N"""
            } else {
              "\"" + v.toString.replaceAll("\"", "\"\"") + "\""
            }
          }
          .mkString("\t") + "\n").getBytes
      }.flatten

      new InputStream {
        override def read(): Int =
          if (bytes.hasNext) {
            bytes.next & 0xff // make the signed byte an unsigned int
          } else {
            -1
          }
      }
    }

    def copyIn(url: String, df: DataFrame, table: String):Unit = {
      var cols = df.columns.mkString(",")

      df.foreachPartition { rows =>
        val conn = DriverManager.getConnection(url)
        try {
          val cm = new CopyManager(conn.asInstanceOf[BaseConnection])
          cm.copyIn(
            s"COPY $table ($cols) " + """FROM STDIN WITH (NULL '\N', FORMAT CSV, DELIMITER E'\t')""",
            rowsToInputStream(rows))
          ()
        } finally {
          conn.close()
        }
      }
    }
  }

Continuing the setup, save some sample data into ``people.json``. Note the intentional lack of surrounding square brackets. Later we'll create a Spark dataframe from the data.

.. code-block:: js

  {"name":"Tanya Rosenau"   , "age": 24},
  {"name":"Rocky Slay"      , "age": 85},
  {"name":"Tama Erdmann"    , "age": 48},
  {"name":"Jared Olivero"   , "age": 42},
  {"name":"Gudrun Shannon"  , "age": 53},
  {"name":"Quentin Yoon"    , "age": 32},
  {"name":"Yanira Huckstep" , "age": 53},
  {"name":"Brendon Wesley"  , "age": 19},
  {"name":"Minda Nordeen"   , "age": 79},
  {"name":"Katina Woodell"  , "age": 83},
  {"name":"Nevada Mckinnon" , "age": 65},
  {"name":"Georgine Mcbee"  , "age": 56},
  {"name":"Mittie Vanetten" , "age": 17},
  {"name":"Lecia Boyett"    , "age": 37},
  {"name":"Tobias Mickel"   , "age": 69},
  {"name":"Jina Mccook"     , "age": 82},
  {"name":"Cassidy Turrell" , "age": 37},
  {"name":"Cherly Skalski"  , "age": 29},
  {"name":"Reita Bey"       , "age": 69},
  {"name":"Keely Symes"     , "age": 34}

Finally, create and distribute a table in Citus:

.. code-block:: sql

  create table spark_test ( name text, age integer );
  select create_distributed_table('spark_test', 'name');

Now we're ready to hook everything together. Start up ``sbt``:

.. code-block:: bash

  # run this in the sparkcitus directory

  sbt

Once inside sbt, compile the project and then go into the "console" which is a Scala repl that loads our code and dependencies:

.. code-block:: text

  sbt:sparkcitus> compile
  [success] Total time: 3 s

  sbt:sparkcitus> console
  [info] Starting scala interpreter...

  scala> 

Type these Scala commands into the console:

.. code-block:: scala

  // inside the sbt scala interpreter

  import org.apache.spark.sql.SparkSession

  // open a session to the Spark cluster
  val spark = SparkSession.builder().appName("sparkcitus").config("spark.master", "local").getOrCreate()

  // load our sample data into Spark
  val df = spark.read.json("people.json")

  // this is a simple connection url (it assumes Citus
  // is running on localhost:5432), but more complicated
  // JDBC urls differ subtly from Postgres urls, see:
  // https://jdbc.postgresql.org/documentation/head/connect.html
  val url = "jdbc:postgresql://localhost/postgres"

  // ingest the data frame using our CopyHelper class
  CopyHelper.copyIn(url, df, "spark_test")

This uses the CopyHelper to ingest the ionformation. At this point the data will appear in the distributed table.

.. note::

  Our method of ingesting the dataframe is straightforward but doesn't protect against Spark errors. Spark guarantees "at least once" semantics, i.e. a read error can cause a subsequent read to encounter previously seen data.

  A more complicated, but robust, approach is to use the custom Spark partitioner `spark-citus <https://github.com/koeninger/spark-citus>`_ so that partitions match up exactly with Citus shards. This allows running transactions directly on worker nodes which can rollback on read failure. See the presentation linked in that repository for more information.
