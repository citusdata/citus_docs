.. _introduction:

Real Time Dashboards
#####################

Citus provides its users real-time responsiveness over large datasets. One workload that
we commonly see at Citus involves powering real-time dashboards over events data.

For example, you could be a cloud services provider helping other businesses serve their
HTTP traffic. In this setup, everytime one of your clients receives an HTTP request, you
generate a log record. You want to ingest all of those records and create an HTTP
analytics dashboard which gives your clients insights, such as the number HTTP errors
their site served. It's important that this data show up with as little latency as
possible so your clients can fix problems with their sites. It's also important to show
graphs of historical trends through a dashboard to your clients.

Or maybe you're building an advertising network and want to show clients clickthrough
rates on their campaigns. In this example, latency is also critical, raw data volume is
also high, and both historical and live data are important.

In this reference architecture we'll demonstrate how to build part of the first example
but this architecture would work equally well for the second and many other use-cases.

Running It Yourself
-------------------

We have `a github repo <https://github.com>`_ with scripts and usage instructions. If
you've gone through our installation instructions for running on either single or multiple
machines you're ready to try it out. There will be code snippets in this tutorial but they
don't specify a complete system, the GitHub repo has all the details in one place.

Data Model
----------

The data we're dealing with is an immutable stream of log data. Here we'll insert directly
into Citus. If you're ingesting billions of log records per day into your cluster, you
could also consider micro-batching these records in a distributed message queue, such as
Kafka.

In this example, we'll use a simple schema for ingesting HTTP event data. This schema
serves as an example to demonstrate the overall architecture; and your schema will likely
have additional columns.

.. code-block:: sql

  -- this gets run on the master
  CREATE TABLE http_request (
    zone_id INT, -- every customer's site is a different "zone"
    event_time TIMESTAMPTZ,

    session_id UUID,
    url TEXT,
    request_country TEXT,
    ip_address CIDR,

    status_code INT,
    response_time_msec INT,
  )
  SELECT master_create_distributed_table('http_request', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_request', 16, 2);

When we call :ref:`master_create_distributed_table <master_create_distributed_table>`
we ask Citus to hash-distribute ``http_request`` using the ``zone_id`` column. That means
that all data for a particular zone will live in the same shard.

When we call :ref:`master_create_worker_shards <master_create_worker_shards>` we tell it
to create 16 shards, and 2 replicas of each shard (for a total of 32 shard replicas).
:ref:`We recommend <faq_choose_shard_count>` using 2-4x as many shards as CPU cores in
your cluster. This way, you can later add worker nodes into your cluster and rebalance
shards across the workers in your cluster.

Using a replication factor of 2 means every row is written to multiple workers. When a
worker fails, the master node will serve queries for any shards that the worker was
responsible for by querying the shard's replicas.

.. NOTE::

  In Citus Cloud, you must use a replication factor of 1. Citus Cloud preconfigures its
  replication and high availability setup, and therefore requires this setting to be 1.

With this, the system is ready to accept data and serve queries! You can run
queries such as:

.. code-block:: sql

  INSERT INTO http_request (
      zone_id, session_id, url, request_country,
      ip_address, status_code, reponse_time_msec
    ) VALUES (
        1, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'http://example.com/path', 'USA',
        cidr '88.250.10.123', 200, 10
    );

And do some dashboard queries like:

.. code-block:: sql

  SELECT
    date_trunc('minute', ingest_time) as minute,
    COUNT(1) AS request_count,
    COUNT(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
    request_count - success_count AS error_count,
    SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
  FROM http_request
  WHERE zone_id = 1 AND minute = date_trunc('minute', now())
  GROUP BY minute;

We've provided `a data ingest script <http://github.com>`_ you can run to generate example
data. There are also a few more `example queries <http://github.com>`_ to play around with
in the github repo.

The above setup will get you pretty far, but it has two drawbacks:

* Your HTTP analytics dashboard must go over each row every time it needs to generate a
  graph. For example, if your clients are interested in trends over the past year, your
  queries will aggregate every row for the past year from scratch.
* Your storage costs will grow proportionally with the ingest rate and the length of the
  queryable history. In practice, you may want to keep raw events for a shorter period of
  time (one month) and look at historical graphs over a longer time period (years).

Rollups
-------

You can overcome these two drawbacks by rolling up raw HTTP events into pre-aggregated
forms. Here, we'll aggregate the raw data into other tables that store 
summaries of 1-minute, 1-hour, and 1-day intervals. These might correspond to zoom-levels
in the dashboard. When the user wants request times for the last month the dashboard can
read and chart the values for each of the last 30 days, no math required! For the rest of
this document, we'll only talk about the first granularity, the 1-minute one. The github
repo has `DDL <http://github.com>`_ for the other resolutions.

.. code-block:: sql

  CREATE TABLE http_request_1min (
        zone_id INT,
        event_time TIMESTAMPTZ, -- which minute this row represents

        error_count INT,
        success_count INT,
        request_count INT,
        average_response_time_msec INT,
        CHECK (request_count = error_count + success_count)
  )
  SELECT master_create_distributed_table('http_requests_1min', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests_1min', 16, 2);
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX ON http_requests_1min (zone_id, ingest_time);

This looks a lot like the previous code block. Most importantly, it also shards on
``zone_id``, and it also uses 16 shards with 2 replicas of each. Because all three of
those match, there's a 1-to-1 correspondence between ``http_request`` shards and
``http_request_1min`` shards, and Citus will place matching shards on the same worker.
This is called colocation; it makes queries such as joins faster and our rollups possible.

.. image:: /images/colocation.png
  :alt: colocation in citus

In order to populate ``http_request_1min`` we're going to periodically run the equivalent
of an INSERT INTO SELECT. Citus doesn't yet support `INSERT INTO SELECT
<https://github.com/citusdata/citus/issues/508>`_ on distributed 
tables, so instead we'll run a function on all the workers which runs INSERT INTO SELECT
on every matching pair of shards. This is possible because shards from the two tables are
colocated on the same machine.

.. code-block:: plpgsql

  -- this should be run on each worker
  CREATE FUNCTION rollup_1min(source_shard text, dest_shard text) RETURNS void
  AS $$
  DECLARE
    v_latest_minute_already_aggregated timestamptz;
    v_new_latest_already_aggregated timestamptz;
  BEGIN
    PERFORM SET lock_timeout 100;
    -- since master calls this function every minute, and future invokations will
    -- do any work this function doesn't do, it's safe to quit if we wait too long
    -- for this FOR UPDATE lock which makes sure at most one instance of this function
    -- runs at a time
    SELECT ingest_time INTO v_latest_minute_already_aggregated FROM rollup_thresholds
      WHERE source_shard = source_shard AND dest_shard = dest_shard
      FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO rollup_thresholds VALUES (
        '1970-01-01', source_shard::regclass, dest_shard::regclass);
      RETURN;
    END IF;
    PERFORM RESET lock_timeout;

    EXECUTE format('
      WITH (
        INSERT INTO %I (
            zone_id, ingest_time, request_count,
            error_count, success_count, average_response_time_msec)
          SELECT
            zone_id,
            date_trunc('minute', ingest_time) as minute,
            COUNT(1) as request_count,
            COUNT(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
            request_count - success_count AS error_count,
            SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
            -- later sections will show some more clauses that can go here
          FROM %I
          WHERE ingest_time > v_latest_minute_already_aggregated
          GROUP BY zone_id, minute
        ) as inserted_rows
      SELECT max(minute) INTO v_new_latest_already_aggregated FROM inserted_rows;
    ', dest_shard, source_shard);

    -- mark how much work we did, so the next invocation picks up where we left off
    PERFORM UPDATE rollup_thresholds
      SET ingest_time = v_new_latest_already_aggregated
      WHERE source_shard = source_shard AND dest_shard = dest_shard;
  END;
  $$ LANGUAGE 'plpgsql';

As discussed above, there's a 1-to-1 correspondence between http_request shards and
``http_request_1min`` shards. This function accepts the name of the ``http_request`` shard
to read from and the name of the ``http_request_1min`` shard to write to.

The function also uses a local table, to keep track of how much of the raw data has
already been aggregated:

.. code-block:: sql

  -- every worker should have their own local version of this table
  CREATE TABLE rollup_thresholds (
        ingest_time timestamptz,
        source_shard regclass,
        dest_shard regclass,
        UNIQUE (source_shard, dest_shard)
  );

Since this function is given some metadata from the master, where does the master get that
metadata from? Every minute it calls its own function which fires off all the
aggregations:

.. code-block:: plpgsql

  -- this should be run on the master
  CREATE FUNCTION run_rollups(source_table text, dest_table text) RETURNS void
  AS $$
  DECLARE
  BEGIN
    FOR source_shard, dest_shard, nodename, nodeport IN
      SELECT
        a.logicalrelid::regclass||'_'||a.shardid,
        b.logicalrelid::regclass||'_'||b.shardid,
        nodename, nodeport
      FROM pg_dist_shard a
      JOIN pg_dist_shard b USING (shardminvalue)
      JOIN pg_dist_shard_placement p ON (a.shardid = p.shardid)
      WHERE a.logicalrelid = 'first'::regclass AND b.logicalrelid = 'second'::regclass;
    LOOP
      SELECT * FROM dblink(
        format('host=%s port=%d', nodename, nodeport),
        format('SELECT rollup_1min(%, %s);', source_shard, dest_shard));
    END LOOP;
  END;
  $$ LANGUAGE 'plpgsql';

.. NOTE::

  There are many ways to make sure the function is called periodically and no answer that
  works well for every system. If you're able to run cron on the same machine as the
  master, you can do something as simple as this:

  .. code-block:: bash
  
    * * * * * psql -c "SELECT run_rollups('http_requests', 'http_requests_1min');"

The dashboard query from earlier is now a lot nicer:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());

Expiring Old Data
-----------------

The rollups make queries faster, but we still need to expire old data to avoid these
shards growing indefinitely. Once you decide how long you'd like to keep data for each
granularity, you could easily write a function to expire old data. In the following
example, we decided to keep raw data for one day and 1-minute aggregations for one month.

.. code-block:: plpgsql

  -- another function for the master
  CREATE FUNCTION expire_old_request_data RETURNS void
  AS $$
    SET citus.all_modification_commutative TO TRUE;
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request WHERE ingest_time < now() - interval ''1 day'';');
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request_1min WHERE ingest_time < now() - interval ''1 month'';');
    RESET citus.all_modification_commutative;
  END;
  $$ LANGUAGE 'sql';

.. NOTE::

  The above function should be called every minute. You could for example do this by
  adding a crontab entry on the master node:

  .. code-block:: bash
  
    * * * * * psql -c "SELECT expire_old_request_data();"

That's the basic architecture! We provided an architecture that ingests HTTP events and
then rolls up these events into their pre-aggregated form. This way, you can both store
raw events and also power your analytical dashboards with subsecond queries.

The next sections extend on the basic architecture and show you how to resolve questions
that often pop up.

Probabilistic Distinct Counts
-----------------------------

One type of question that we often here is :ref:`approximate distinct counts
<approx_dist_count>` using HLLs. How many unique visitors visited your site over the past
month? Answering this question requires storing the list of all previously-seen visitors in the
rollup tables, a prohibitively large amount of data. Rather than answer the query exactly,
we can answer the query approximately, using a datatype called HyperLogLog, or HLL. This
data type takes a surprisingly small amount of space to tell you approximately how many
unique elements are in the set you pass it. This data type's accuracy can be
adjusted. We'll use ones which, using only 1280 bytes, will be able to count up to tens of
billions of unique visitors with at most 2.2% error.

An equivalent problem appears if you want to run a global query, such has the number of
unique IP addresses who visited any site over some time period. Without HLLs this query
involves shipping lists of ip addresses from the workers to the master for it to
deduplicate. That's both a lot of network traffic and a lot of computation. By using HLLs
you can greatly improve query speed.

First you must install the hll extension; `the github repo
<https://github.com/aggregateknowledge/postgresql-hll>`_ has instructions. Next, you have
to enable it:

.. code-block:: sql

  -- this part must be run on all workers
  CREATE EXTENSION hll;

  -- this part runs on the master
  ALTER TABLE http_requests_1min ADD COLUMN distinct_sessions (hll);

When doing our rollups, you can now aggregate sessions into an HLL column with queries
like this:

.. code-block:: sql

  SELECT
    zone_id, date_trunc('minute', ingest_time) as minute,
    hll_add_agg(hll_hash_text(session_id)) AS distinct_sessions
  WHERE minute = date_trunc('minute', now())
  FROM http_request
  GROUP BY zone_id, minute;

Now dashboard queries are a little more complicated. You need to read the distinct number
of sessions using the ``hll_cardinality`` function:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    hll_cardinality(distinct_sessions) AS distinct_session_count
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());

HLLs aren't just faster, they also let you do things you couldn't previously. Say we did
our rollups, but instead of using HLLs, we saved the exact unique counts. This works fine,
but you can't answer queries such as "how many distinct sessions were there during this
one-week period in the past we've thrown away the raw data for?".

With HLLs, this is easy. You'll first need to inform Citus about the ``hll_union_agg``
aggregate function and its semantics. You do this by running the following:

.. code-block:: sql

  -- this should be run on the workers and master
  CREATE AGGREGATE sum (hll)
  (
    sfunc = hll_union_agg,
    stype = internal,
  );

Now, when you call SUM over a collection of HLLs, PostgreSQL will return the HLL for us.
You can then compute distinct session counts over a time period with the following query:

.. code-block:: sql

  -- working version of the above query
  SELECT
    hll_cardinality(SUM(distinct_sessions))
  FROM http_request_1day
  WHERE ingest_time BETWEEN timestamp '06-01-2016' AND '06-08-2016';

You can find more information on HLLs `in the project's GitHub repository
<https://github.com/aggregateknowledge/postgresql-hll>`_.


Unstructured Data with JSONB
----------------------------

Citus also works well with Postgres' semi-structured data types. To demonstrate this,
let's keep track of the number of visitors that came from each country.
Using a semi-structured data type saves you from needing to add a column for every
individual country and ending up with rows that have hundreds of sparsely filled columns.
We have `a blog post
<https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_ explaining
which format to use for your semi-structured data. This blog post recommends JSONB as the
semi-structured data type of choice; and we demonstrate how to incorporate JSONB columns
into your data model in the following.

First, you'll add the new column to our rollup table:

.. code-block:: sql

  ALTER TABLE http_requests_1min ADD COLUMN country_counters (JSONB);

Next, you'll need to include it in the rollups by adding a query like this to the rollup
function:

.. code-block:: sql

  SELECT
    zone_id, minute,
    hll_union_agg(distinct_sessions) AS distinct_sessions,
    jsonb_object_agg(request_country, country_count)
  FROM (
    SELECT
      zone_id, date_trunc('minute', ingest_time) as minute,
      hll_add_agg(hll_hash_text(session_id)) AS distinct_sessions,
      request_country,
      count(1) AS country_count
    WHERE minute = date_trunc('minute', now())
    FROM http_request
    GROUP BY zone_id, minute, request_country
  )
  GROUP BY zone_id, minute;

Now, if you want to get the number of requests which came from the United States in your
dashboard, your can modify the dashboard query to look like this:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    hll_cardinality(distinct_sessions) as distinct_session_count,
    country_counters->'USA' AS american_visitors
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());

Summary
-------

This article shows a complete system that stores raw events data and rolls them up within
the same distributed database. We started by capturing raw HTTP events, and then showed
how to roll up these events to serve real-time dashboards. We next talked using an example
PostgreSQL extension, HyperLogLog (HLL) to provide probabilistic distinct counts. We
conclued by introducing JSONB, a powerful semi-structured data type.
