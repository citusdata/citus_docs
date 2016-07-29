.. _introduction:

Real Time Analytics
#####################

Over the last few years we've helped many different kinds of clients use Citus and noticed
a technical problem many businesses have: running real-time analytics over large streams
of data.

For example, say you're building an HTTP analytics dashboard. You have enough clients that
around every millisecond a user hits one of their websites and sends a log record to you.
You want to ingest all of those records (1000 inserts/sec) and create a dashboard which
shows your clients things like how many requests to their sites are errors. It's important
that this data show up with as little latency as possible so your clients can fix problems
with their sites. It's also useful to show graphs of historical data, however keeping all
the raw data around forever is prohibitively expensive.

Or maybe you're building an advertising network and want to show clients clickthrough
rates on their campaigns. Likewise, you want to ingest lots of data with as little latency
as possible and show both historical and live data on a dashboard.

In this reference architecture we'll demonstrate how to build part of the first example
but this architecture would work equally well for the second and many other business
use-cases.

Running It Yourself
-------------------

There's `a github repo <http://github.com>`_ with scripts and usage instructions. If
you've gone through our installation instructions for running on either single or multiple
machines you're ready to try it out. There will be some code snippets in this tutorial
but the github repo has all the details in one place.

Data Model
----------

The data we're dealing with is an immutable stream of log data. Here we'll insert directly
into Citus but it's also common for this data to first be routed through something like
Kafka. Doing so makes the system a little more resilient to failures, lets the data be
routed to multiple places (such as a warehouse like redshift), and (once data volumes
become unmanageably high) makes it a little easier to start pre-aggregating the data
before inserting.

In this example, the raw data will use the following schema which isn't very realistic as
far as http analytics go but sufficient for showing off the architecture we have in mind.

.. code-block:: sql

  -- this gets run on the master
  CREATE TABLE http_request (
    zone_id INT,
    ingest_time TIMESTAMPTZ DEFAULT now(),

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
we're telling it to hash-distribute using the `zone_id` column. That means dashboard
queries will each hit a single shard.

When we call :ref:`master_create_worker_shards <master_create_worker_shards>` we tell it
to create 16 shards, and 2 copies of each shard. :ref:`We recommend
<faq_choose_shard_count>` using 2-4x as many shards as cores in your cluster, this reduces
the overhead of keeping track of lots of shards but also leaves you plenty of shards to
spread around when you scale up your cluster by adding workers.

Using a replication factor of 2 (or any number > 1, really), means data is written to
multiple workers. When a node fails the worker will serve queries for a shard using the
other node so you don't have any downtime.

.. NOTE::

  In Citus Cloud you must use a replication factor of 1 (instead of the 2 used here), as
  they have a different HA solution.

With this, the system is already ready to accept data and serve queries. You can run
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
    COUNT(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,

    SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
  FROM http_request
  WHERE zone_id = 1 AND minute = date_trunc('minute', now())
  GROUP BY minute;

We've provided `a data ingest script <http://github.com>`_ you can run to generate example
data. There are also a few more `example queries <http://github.com>`_ to play around with
in the github repo.

This will get us pretty far, but means that dashboard queries must aggregate every row in
the target time range for every query they answer. It also means storage costs will grow
proportionately with the ingest rate and length of queryable history.

Rollups
-------

In order to fix both problems, let's start rolling up data. The raw data will be
aggregated into other tables which store the same data in 1-minute, 1-hour, and 1-day
intervals. These correspond to zoom-levels in the dashboard. When the user wants request
times for the last month the dashboard can read and chart the values for each of the last
30 days.

.. code-block:: sql

  CREATE TABLE http_request_1min (
        zone_id INT,
        ingest_time TIMESTAMPTZ,

        error_count INT,
        success_count INT,
        request_count INT,
        average_response_time_msec INT,
  )
  SELECT master_create_distributed_table('http_requests_1min', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests_1min', 16, 2);
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX ON http_requests_1min (zone_id, ingest_time);

The github repo has `DDL commands <http://github.com>`_ for the other granularities, for
now we'll only talk about this one. Because we're distributing this table by the same
key as we hashed the http_request table (zone_id), and we use the same number of shards
and the same replication factor, there's a 1-to-1 correspondence between http_request
shards and http_request_1min shards. Because of this correspondence, Citus puts the
matching shards onto the same machine. This means that rollups don't involve any network
transfer, data for a row will always belong on the same machine. We call this colocation
and it makes many kinds of queries (such as joins) far faster.

In order to populate this table we're going to periodically run the equivalent of an
INSERT INTO SELECT. However, Citus doesn't yet support INSERT INTO SELECT on distributed
tables, so we're going to run it on each of the workers. Here's the function that does
the update:

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
            request_count - success_count AS error_count
    
            SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
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

That function assumes the existence of a local table to keep track of which rows have
been aggregated:

.. code-block:: sql

  -- this should also be run on each worker
  CREATE TABLE rollup_thresholds (
        ingest_time timestamptz,
        source_shard regclass,
        dest_shard regclass,
        UNIQUE (source_shard, dest_shard)
  );

As discussed above, there's a 1-to-1 correspondence between http_request shards and
http_request_1min shards. This function accepts the name of the http_request shard to
read from and the name of the http_request_1min shard to write to. It can't figure it
out itself because that kind of metadata is kept on the master, not the workers.

That means, the master must call this function on each pair of shards. Every minute it
calls its own function:

.. code-block:: crontab

  # added to the master's crontab:
  * * * * * psql -c "SELECT run_rollups();"

Which reads the metadata and fires off all the aggregations:

.. code-block:: plpgsql

  -- this should be run on the master
  CREATE FUNCTION run_rollups RETURNS void
  AS $$
  DECLARE
  BEGIN
        -- SELECT node_name FROM master_get_active_worker_nodes()
        -- do some dblink magic?
  END;
  $$ LANGUAGE 'plpgsql';

The dashboard query from earlier is now a lot nicer:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());

Expiring Old Data
-----------------

The rollups make queries faster but we still have a lot of raw data sitting around. How
long you should keep each granularity of data is a business decision, but once you decide
it's easy to write a script to expire old data:

.. code-block:: crontab

  # another master crontab entry
  * * * * * psql -c "SELECT expire_old_request_data();"
    
Where the function looks something like this:

.. code-block:: sql

  -- another master function
  CREATE FUNCTION expire_old_request_data RETURNS void
  AS $$
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request WHERE ingest_time < now() - interval \'1 hour\';);
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request_1min WHERE ingest_time < now() - interval \'1 day\';);
  $$ LANGUAGE SQL;

Approximate Distinct Counts
---------------------------

One kind of query we're particularily proud of is :ref:`approximate distinct counts
<approx_dist_count>` using HLLs. How many unique visitors visited your site over some time
period? Answering it requires storing the list of all previously-seen visitors in the
rollup tables, a prohibitively large amount of data. Rather than answer the query exactly,
we can answer the query approximately, using a datatype called hyperloglog, or HLL, which
takes a surprisingly small amount of space to tell you approximately how many unique
elements are in the set you pass it. Their accuracy can be adjusted, we'll use ones which,
using only [xxx]kb, will be able to count up to billions of unique visitors with at most
[xxx]% error.

An equivalent problem appears if you want to run a global query, such has the number of
unique ip addresses who visited any site over some time period. Without HLLs this query
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

When doing our rollups, we can now aggregate sessions into an hll column with queries
like this:

.. code-block:: sql

  SELECT
    zone_id, date_trunc('minute', ingest_time) as minute,
    hll_add_agg(hll_hash_text(session_id)) AS distinct_sessions
  WHERE minute = date_trunc('minute', now())
  FROM http_request
  GROUP BY zone_id, minute;

Now dashboard queries are a little more complicated, you have to read out the cardinality
during SELECT:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    hll_cardinality(distinct_sessions) AS distinct_session_count
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());

HLLs aren't just faster, they let you do things you couldn't previously. Say we did our
rollups, but instead of using HLLs we saved the exact unique counts. This works fine, but
you can't answer queries such as "how many distinct sessions were there during this
one-week period in the past we've thrown away the raw data for?". With HLLs, it's easy:

.. code-block:: sql

  -- careful, doesn't work!
  SELECT
    hll_cardinality(hll_union_agg(distinct_sessions))
  FROM http_request_1day
  WHERE ingest_time BETWEEN timestamp '06-01-2016' AND '06-08-2016';

Well, it would be easy, except since Citus `can't yet
<https://github.com/citusdata/citus/issues/120>`_ push down aggregates such as
hll_union_agg. Instead you have to do a bit of trickery:

.. code-block:: sql

  -- this should be run on the workers and master
  CREATE AGGREGATE sum (hll)
  (
    sfunc = hll_union_agg,
    stype = internal,
  );

Now, when we call SUM over a collection of hlls, postgresql will return the hll for us.
This lets us write the above query as:

.. code-block:: sql

  -- working version of the above query
  SELECT
    hll_cardinality(SUM(distinct_sessions))
  FROM http_request_1day
  WHERE ingest_time BETWEEN timestamp '06-01-2016' AND '06-08-2016';

More information on HLLs can be found in `their github repo
<https://github.com/aggregateknowledge/postgresql-hll>`_.

HLLS are an example from the postgresql community, but there are a couple extensions we've
written ourselves which do the same thing (improve performance and storage requirements)
for different kinds of queries. This includes `count-min sketch
<https://github.com/citusdata/cms_topn>`_ for
top-n queries, and `HDR <https://github.com/citusdata/HDR>`_, for percentile queries.

Unstructured Data with JSONB
----------------------------

Citus works well with Postgres' built-in support for unstructured data types. To
demonstrate this, let's keep track of the number of visitors which came from each country.
Using a semi-structure data type saves you from needing to add a column for every
individual country and blowing up your row width.  We have `a blog post
<https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_ explaining
which format to use for your semi-structured data. It says you should usually use jsonb
but never says how. Let's correct that :)

First, add the new column to our rollup table:

.. code-block:: sql

  ALTER TABLE http_requests_1min ADD COLUMN country_counters (JSONB);

Next, include it in the rollups by adding a query like this to the rollup function:

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

Now, if you want to get the number of requests which came from america in your dashboard,
your can modify the dashboard query to look like this:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec,
    hll_cardinality(distinct_sessions) as distinct_session_count,
    country_counters->'USA' AS american_visitors
  FROM http_request_1min
  WHERE zone_id = 1 AND minute = date_trunc('minute', now());
