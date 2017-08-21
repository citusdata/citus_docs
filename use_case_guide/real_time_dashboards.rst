.. _introduction:

Real Time Dashboards
#####################

Citus provides real-time queries over large datasets. One workload we commonly see at
Citus involves powering real-time dashboards of event data.

For example, you could be a cloud services provider helping other businesses monitor their
HTTP traffic. Every time one of your clients receives an HTTP request your service
receives a log record. You want to ingest all those records and create an HTTP analytics
dashboard which gives your clients insights such as the number HTTP errors their sites
served. It's important that this data shows up with as little latency as possible so your
clients can fix problems with their sites. It's also important for the dashboard to show
graphs of historical trends.

Alternatively, maybe you're building an advertising network and want to show clients
clickthrough rates on their campaigns. In this example latency is also critical, raw data
volume is also high, and both historical and live data are important.

In this section we'll demonstrate how to build part of the first example, but this
architecture would work equally well for the second and many other use-cases.

Running It Yourself
-------------------

There will be code snippets in this tutorial but they don't specify a complete system.
There's `a github repo <https://github.com/citusdata/realtime-dashboards-resources>`_ with
all the details in one place. If you've followed our installation instructions for running
Citus on either a single or multiple machines you're ready to try it out.

Data Model
----------

The data we're dealing with is an immutable stream of log data. We'll insert directly into
Citus but it's also common for this data to first be routed through something like Kafka.
Doing so has the usual advantages, and makes it easier to pre-aggregate the data once data
volumes become unmanageably high.

We'll use a simple schema for ingesting HTTP event data. This schema serves as an example
to demonstrate the overall architecture; a real system might use additional columns.

.. code-block:: sql

  -- this is run on the coordinator

  CREATE TABLE http_request (
    site_id INT,
    ingest_time TIMESTAMPTZ DEFAULT now(),

    url TEXT,
    request_country TEXT,
    ip_address TEXT,

    status_code INT,
    response_time_msec INT
  );

  SELECT create_distributed_table('http_request', 'site_id');

When we call :ref:`create_distributed_table <create_distributed_table>`
we ask Citus to hash-distribute ``http_request`` using the ``site_id`` column. That means
all the data for a particular site will live in the same shard.

The UDF uses the default configuration values for shard count. We
recommend :ref:`using 2-4x as many shards <faq_choose_shard_count>` as
CPU cores in your cluster. Using this many shards lets you rebalance
data across your cluster after adding new worker nodes.

.. NOTE::

  Citus Cloud uses `streaming replication <https://www.postgresql.org/docs/current/static/warm-standby.html>`_ to achieve high availability and thus maintaining shard replicas would be redundant. In any production environment where streaming replication is unavailable, you should set ``citus.shard_replication_factor`` to 2 or higher for fault tolerance.

With this, the system is ready to accept data and serve queries! We've provided `a data
ingest script
<https://github.com/citusdata/realtime-dashboards-resources/blob/master/ingest_example_data.sql>`_
you can run to generate example data. Once you've ingested data, you can run dashboard
queries such as:

.. code-block:: sql

  SELECT
    date_trunc('minute', ingest_time) as minute,
    COUNT(1) AS request_count,
    SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
    SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
  FROM http_request
  WHERE site_id = 1 AND date_trunc('minute', ingest_time) > now() - interval '5 minutes'
  GROUP BY minute;
 
The setup described above works, but has two drawbacks:

* Your HTTP analytics dashboard must go over each row every time it needs to generate a
  graph. For example, if your clients are interested in trends over the past year, your
  queries will aggregate every row for the past year from scratch.
* Your storage costs will grow proportionally with the ingest rate and the length of the
  queryable history. In practice, you may want to keep raw events for a shorter period of
  time (one month) and look at historical graphs over a longer time period (years).

Rollups
-------

You can overcome both drawbacks by rolling up the raw data into a pre-aggregated form.
Here, we'll aggregate the raw data into a table which stores summaries of 1-minute
intervals. In a production system, you would probably also want something like 1-hour and
1-day intervals, these each correspond to zoom-levels in the dashboard. When the user
wants request times for the last month the dashboard can simply read and chart the values
for each of the last 30 days.

.. code-block:: sql

  CREATE TABLE http_request_1min (
        site_id INT,
        ingest_time TIMESTAMPTZ, -- which minute this row represents

        error_count INT,
        success_count INT,
        request_count INT,
        average_response_time_msec INT,
        CHECK (request_count = error_count + success_count),
        CHECK (ingest_time = date_trunc('minute', ingest_time))
  );

  SELECT create_distributed_table('http_request_1min', 'site_id');
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX http_request_1min_idx ON http_request_1min (site_id, ingest_time);

This looks a lot like the previous code block. Most importantly: It also shards on
``site_id`` and uses the same default configuration for shard count and
replication factor. Because all three of those match, there's a 1-to-1
correspondence between ``http_request`` shards and ``http_request_1min`` shards,
and Citus will place matching shards on the same worker. This is called
:ref:`co-location <colocation>`; it makes queries such as joins faster and our rollups possible.

.. image:: /images/colocation.png
  :alt: co-location in citus

In order to populate ``http_request_1min`` we're going to periodically run the equivalent
of an INSERT INTO SELECT. We'll run a function on all the workers which runs INSERT INTO SELECT
on every matching pair of shards. This is possible because the tables are co-located.

.. code-block:: plpgsql

    -- this function is created on the workers
    CREATE FUNCTION rollup_1min(p_source_shard text, p_dest_shard text) RETURNS void
    AS $$
    BEGIN
      -- the dest shard will have a name like: http_request_1min_204566, where 204566 is the
      -- shard id. We lock using that id, to make sure multiple instances of this function
      -- never simultaneously write to the same shard.
      IF pg_try_advisory_xact_lock(29999, split_part(p_dest_shard, '_', 4)::int) = false THEN
        -- N.B. make sure the int constant (29999) you use here is unique within your system
        RETURN;
      END IF;
    
      EXECUTE format($insert$
        INSERT INTO %2$I (
          site_id, ingest_time, request_count,
          success_count, error_count, average_response_time_msec
        ) SELECT
          site_id,
          date_trunc('minute', ingest_time) as minute,
          COUNT(1) as request_count,
          SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
          SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
          SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
        FROM %1$I
        WHERE
          date_trunc('minute', ingest_time)
            > (SELECT COALESCE(max(ingest_time), timestamp '10-10-1901') FROM %2$I)
          AND date_trunc('minute', ingest_time) < date_trunc('minute', now())
        GROUP BY site_id, minute
        ORDER BY minute ASC;
      $insert$, p_source_shard, p_dest_shard);
    END;
    $$ LANGUAGE 'plpgsql';

Inside this function you can see the dashboard query from earlier. It's been wrapped in
some machinery which writes the results into ``http_request_1min`` and allows passing in
the name of the shards to read and write from. It also takes out an advisory lock, to
ensure there aren't any concurrency bugs where the same rows are written multiple times.

The machinery above which accepts the names of the shards to read and write is necessary
because only the coordinator has the metadata required to know what the shard pairs are. It has
its own function to figure that out:

.. code-block:: plpgsql

    -- this function is created on the coordinator
    CREATE FUNCTION colocated_shard_placements(left_table REGCLASS, right_table REGCLASS)
    RETURNS TABLE (left_shard TEXT, right_shard TEXT, nodename TEXT, nodeport BIGINT) AS $$
      SELECT
        a.logicalrelid::regclass||'_'||a.shardid,
        b.logicalrelid::regclass||'_'||b.shardid,
        nodename, nodeport
      FROM pg_dist_shard a
      JOIN pg_dist_shard b USING (shardminvalue)
      JOIN pg_dist_placement p ON (a.shardid = p.shardid)
      JOIN pg_node n ON (p.groupid = n.groupid)
      WHERE a.logicalrelid = left_table AND b.logicalrelid = right_table;
    $$ LANGUAGE 'sql';

Using that metadata, every minute it runs a script which calls ``rollup_1min`` once for
each pair of shards:

.. code-block:: bash

   #!/usr/bin/env bash
   
   QUERY=$(cat <<END
     SELECT * FROM colocated_shard_placements(
       'http_request'::regclass, 'http_request_1min'::regclass
     );
   END
   )
   
   COMMAND="psql -h \$2 -p \$3 -c \"SELECT rollup_1min('\$0', '\$1')\""
   
   psql -tA -F" " -c "$QUERY" | xargs -P32 -n4 sh -c "$COMMAND"

.. NOTE::

  There are many ways to make sure the function is called periodically and no answer that
  works well for every system. If you're able to run cron on the same machine as the
  coordinator, and assuming you named the above script ``run_rollups.sh``, you can do something
  as simple as this:

  .. code-block:: bash
  
     * * * * * /some/path/run_rollups.sh

The dashboard query from earlier is now a lot nicer:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec
  FROM http_request_1min
  WHERE site_id = 1 AND date_trunc('minute', ingest_time) > date_trunc('minute', now()) - interval '5 minutes';

Expiring Old Data
-----------------

The rollups make queries faster, but we still need to expire old data to avoid unbounded
storage costs. Once you decide how long you'd like to keep data for each granularity, you
could easily write a function to expire old data. In the following example, we decided to
keep raw data for one day and 1-minute aggregations for one month.

.. code-block:: plpgsql

  -- another function for the coordinator
  CREATE OR REPLACE FUNCTION expire_old_request_data() RETURNS void
  AS $$
  BEGIN
    SET citus.all_modification_commutative TO TRUE;
    PERFORM master_modify_multiple_shards(
              'DELETE FROM http_request WHERE ingest_time < now() - interval ''1 day'';');
    PERFORM master_modify_multiple_shards(
              'DELETE FROM http_request_1min WHERE ingest_time < now() - interval ''1 month'';');
  END;
  $$ LANGUAGE 'plpgsql';

.. NOTE::

  The above function should be called every minute. You could do this by adding a crontab
  entry on the coordinator node:

  .. code-block:: bash
  
    * * * * * psql -c "SELECT expire_old_request_data();"

That's the basic architecture! We provided an architecture that ingests HTTP events and
then rolls up these events into their pre-aggregated form. This way, you can both store
raw events and also power your analytical dashboards with subsecond queries.

The next sections extend upon the basic architecture and show you how to resolve questions
which often appear.

Approximate Distinct Counts
---------------------------

A common question in http analytics deals with :ref:`approximate distinct counts
<count_distinct>`: How many unique visitors visited your site over the last month?
Answering this question exactly requires storing the list of all previously-seen visitors
in the rollup tables, a prohibitively large amount of data. A datatype called hyperloglog,
or HLL, can answer the query approximately; it takes a surprisingly small amount of space
to tell you approximately how many unique elements are in a set you pass it. Its accuracy
can be adjusted. We'll use ones which, using only 1280 bytes, will be able to count up to
tens of billions of unique visitors with at most 2.2% error.

An equivalent problem appears if you want to run a global query, such as the number of
unique ip addresses which visited any of your client's sites over the last month. Without
HLLs this query involves shipping lists of ip addresses from the workers to the coordinator for
it to deduplicate. That's both a lot of network traffic and a lot of computation. By using
HLLs you can greatly improve query speed.

First you must install the hll extension; `the github repo
<https://github.com/aggregateknowledge/postgresql-hll>`_ has instructions. Next, you have
to enable it:

.. code-block:: sql

  -- this part must be run on all nodes
  CREATE EXTENSION hll;

  -- this part runs on the coordinator
  ALTER TABLE http_request_1min ADD COLUMN distinct_ip_addresses hll;

When doing our rollups, we can now aggregate sessions into an hll column with queries
like this:

.. code-block:: sql

  SELECT
    site_id, date_trunc('minute', ingest_time) as minute,
    hll_add_agg(hll_hash_text(ip_address)) AS distinct_ip_addresses
  FROM http_request
  WHERE date_trunc('minute', ingest_time) = date_trunc('minute', now())
  GROUP BY site_id, minute;

Now dashboard queries are a little more complicated, you have to read out the distinct
number of ip addresses by calling the ``hll_cardinality`` function:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    hll_cardinality(distinct_ip_addresses) AS distinct_ip_address_count
  FROM http_request_1min
  WHERE site_id = 1 AND ingest_time = date_trunc('minute', now());

HLLs aren't just faster, they let you do things you couldn't previously. Say we did our
rollups, but instead of using HLLs we saved the exact unique counts. This works fine, but
you can't answer queries such as "how many distinct sessions were there during this
one-week period in the past we've thrown away the raw data for?".

With HLLs, this is easy. You'll first need to inform Citus about the ``hll_union_agg``
aggregate function and its semantics. You do this by running the following:

.. code-block:: sql

  -- this should be run on the workers and coordinator
  CREATE AGGREGATE sum (hll)
  (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
  );


Now, when you call SUM over a collection of HLLs, PostgreSQL will return the HLL for us.
You can then compute distinct ip counts over a time period with the following query:

.. code-block:: sql

  SELECT
    hll_cardinality(SUM(distinct_ip_addresses))
  FROM http_request_1min
  WHERE ingest_time BETWEEN timestamp '06-01-2016' AND '06-28-2016';

You can find more information on HLLs `in the project's GitHub repository
<https://github.com/aggregateknowledge/postgresql-hll>`_.

Unstructured Data with JSONB
----------------------------

Citus works well with Postgres' built-in support for unstructured data types. To
demonstrate this, let's keep track of the number of visitors which came from each country.
Using a semi-structure data type saves you from needing to add a column for every
individual country and ending up with rows that have hundreds of sparsely filled columns.
We have `a blog post
<https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_ explaining
which format to use for your semi-structured data. The post recommends JSONB, here we'll
demonstrate how to incorporate JSONB columns into your data model.

First, add the new column to our rollup table:

.. code-block:: sql

  ALTER TABLE http_request_1min ADD COLUMN country_counters JSONB;

Next, include it in the rollups by adding a clause like this to the rollup function:

.. code-block:: sql

  SELECT
    site_id, minute,
    jsonb_object_agg(request_country, country_count)
  FROM (
    SELECT
      site_id, date_trunc('minute', ingest_time) AS minute,
      request_country,
      count(1) AS country_count
    FROM http_request
    GROUP BY site_id, minute, request_country
  ) AS subquery
  GROUP BY site_id, minute;

Now, if you want to get the number of requests which came from america in your dashboard,
your can modify the dashboard query to look like this:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    country_counters->'USA' AS american_visitors
  FROM http_request_1min
  WHERE site_id = 1 AND ingest_time = date_trunc('minute', now());

Resources
---------

This article shows a complete system to give you an idea of what building a non-trivial
application with Citus looks like. Again, there's `a github repo
<https://github.com/citusdata/realtime-dashboards-resources>`_ with all the scripts
mentioned here.

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'real-time', section: 'ref'});
  </script>
