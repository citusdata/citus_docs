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
become unmanageable high) makes it a little easier to start pre-aggregating the data
before inserting.

In this example, the raw data will use the following schema which isn't very realistic as
far as http analytics go but sufficient for showing off the architecture we have in mind.

.. code-block:: sql

  CREATE TABLE http_requests (
    zone_id INT,
    ingest_time TIMESTAMPTZ DEFAULT now(),

    session_id UUID,
    url TEXT,
    request_country TEXT,
    ip_address CIDR,

    status_code INT,
    response_time_msec INT,
  )
  SELECT master_create_distributed_table('http_requests', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests', 16, 2);

When we call master_create_distributed_table we're telling it to hash-distribute using
the `zone_id` column. That means dashboard queries will each hit a single shard.

When we call master_create_worker_shards we tell it to create 16 shards, and 2 copies of
each shard. `We recommend
<http://docs.citusdata.com/en/v5.1/faq/faq.html#how-do-i-choose-the-shard-count-when-i-hash-partition-my-data>`_
using 2-4x as many shards as cores in your cluster, this reduces the overhead of keeping
track of lots of shards, but also leaves you plenty of shards to spread around when you
scale up your cluster by adding workers.

Using a replication factor of 2 (or any number > 1, really), means data is written to
multiple workers, when a node fails the other shard will be used instead.

Note: In Citus Cloud you must use a replication factor of 1, as they have a different HA
solution.

.. code-block:: sql

  CREATE TABLE http_requests_1min (
        zone_id INT,
        ingest_time TIMESTAMPTZ,

        error_count INT,
        success_count INT,
        average_response_time_msec INT,
  )
  SELECT master_create_distributed_table('http_requests_1min', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests_1min', 16, 2);
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX ON http_requests_1min (zone_id, ingest_time);

- Run the data ingest script we've provided and some of these example queries

- As described earlier, this has a few problems. In the next section we
  introduce rollups to solve those problems.

This will get us pretty far, but means that dashboard queries must aggregate every row
in the target time range for every query it answers... pretty slow! It also means that
storage costs will grow proportionately with the ingest rate and length of queryable
history.

In order to fix both problems, let's start rolling up data. The raw data will be
aggregated into other tables which store the same data in 1-minute, 1-hour, and 1-day
intervals. These correspond to zoom-levels in the dashboard. When the user wants request
times for the last month the dashboard can read and chart the values for the last 30 days.
 
Example Queries
---------------

This example is designed to support queries from two broad categories: queries specific
to a site or client (which can have multiple sites) and global queries. To understand the
differences between them it's important to know how Citus stores data. Distributed tables
are stored as collections of shards, each shard residing on one of the worker nodes. In
this architecture we hash-partition on the customer_id, which means all the data for a
single customer lives on the same machines.

Site/Client Queries: This is the bulk of the load on the system, since it's the type of
queries that dashboard will emit. Because all the data for a client lives on the same
machines these queries will hit one machine, minimizing time spent waiting for the
network. They won't benefit from any parallelization but they generally involve reading a
small number of rows.

Global Queries: An analyst might want to know which customer served the most requests
during the last week. This query requires accessing data from across the cluster. If you
were to use postgres it would take a while to access every row in parallel, but Citus
parallelizes the query so that it returns quickly.

Rollups
-------

- We're going to do the equivalent of a INSERT INTO ... SELECT ...
- There's a pl/pgsql function on the workers
- The master, every minute (by cron), reads metadata and calls the function on each shard pair
- Use lock_timeout so you don't get a bunch of these queued up

- There's a local table on each worker keeping track of the high-water mark for each:

.. code-block:: sql

  -- this should be run on each worker
  CREATE TABLE rollup_thresholds (
        ingest_time timestamptz,
        granulatiry text,
  );

- There's a function on each worker which aggregates 

.. code-block:: sql

  -- this should also be run on each worker
  CREATE FUNCTION rollup_1min(source_shard text, dest_shard text) RETURNS void
  AS $$
  DECLARE
        v_latest_minute_already_aggregated timestamptz;
        v_new_latest_already_aggregated timestamptz;
  BEGIN
        PERFORM SET lock_timeout 100;
        SELECT ingest_time INTO v_latest_minute_already_aggregated FROM rollup_thresholds
                WHERE granularity = '1minute'
                FOR UPDATE;
        PERFORM RESET lock_timeout;
        IF NOT FOUND THEN
          -- create the row and lock it... can we upsert here?
        END IF;

        INSERT INTO dest_shard::regclass (zone_id, ingest_time, error_count)
                SELECT zone_id, ingest_time, count(1)
                FROM source_shard::regclass 
                WHERE ingest_time > v_latest_minute_already_aggregated
                GROUP BY zone_id
                RETURNING INTO v_new_latest_already_aggregated

        PERFORM UPDATE rollup_thresholds
                SET ingest_time = v_new_latest_already_aggregated
                WHERE granularity = '1minute';
  END;
  $$ LANGUAGE 'plpgsql';

- there are matching functions for the other two granularities

- on the master you have:

.. code-block:: sql

  -- this is a file called create.sql

.. code-block:: crontab

  # this goes in your crontab
  * * * * * psql -tA -F" " -c "SELECT node_name FROM master_get_active_worker_nodes()" |
    xargs -n1 psql -f create.sql -h

Approximate Distinct Counts
---------------------------

One kind of query we're particularily proud of is :ref:`approximate distinct counts
<approx_dist_count>` using HLLs. How many unique visitors visited your site over some time
period? Answering it requires storing the list of all previously-seen visitors in the
rollup tables, a prohibitively large amount of data. An alternative technique is to use a
datatype called hyperloglog, or HLL, which takes a surprisingly small amount of space to
tell you approximately how many unique elements are part of the set you have it. Their
accuracy can be adjusted, we'll use ones which, using only 2kb, will be able to count up
to billions of unique visitors with at most 5% error.

How many unique visitors visited any site over some time period? Without HLLs this query
involves shipping the list of all visitors from the workers to the master and then doing a
merge on the master. That's both a lot of network traffic and a lot of computation. By
using HLLs you can greatly improve query speed.

First you must enable the extension:

.. code-block:: sql

  CREATE EXTENSION hll;
  ALTER TABLE http_requests_1min ADD COLUMN distinct_sessions (hll);

- Modify the rollups to also compute the hll
- Here's a query you might run to get out the cardinality
- Redefine SUM to run ad-hoc queries, here's an ad-hoc query you might run
- We also have some more exotic data types, such as count-min sketch and topn.

Unstructured Data with JSONB
----------------------------

Citus works well with Postgres' built-in support for JSON data types.

- We have `a blog post
  <https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_
  explaining which format to use for your semi-structured data. It says you should
  usually use jsonb but never says how. A section here will go over an example usage of
  JSONB.

.. code-block:: sql

  ALTER TABLE http_requests_1min ADD COLUMN country_counters (JSONB);
