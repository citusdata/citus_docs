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
machines you're ready to try it out. There will be some code snippets in this tutorial,
but the github repo has all the details in one place.

Data Model
----------

The data we're dealing with is an immutable stream of log data. Here we'll insert directly
into Citus but it's also common for this data to first be routed through something like
Kafka. Doing so makes the system a little more resilient to failures, lets the data be
routed to multiple places (such as a warehouse like redshift), and makes it a little
easier to later pre-aggregate the data before inserting once data volumes become
unmanageably high.

In this example, the raw data will use the following schema which isn't very realistic as
far as http analytics go but sufficient for showing off the architecture we have in mind.

::

  CREATE TABLE http_requests (
    ingest_time TIMESTAMPTZ DEFAULT now(),
    zone_id INT,

    session_id UUID,
    url TEXT,
    request_country TEXT,
    ip_address CIDR,

    status_code INT,
    response_time_msec INT,
  )

We'll :ref:`hash-distribute this table <hash_distribution>` by the `zone_id` column,
meaning all the data for a single zone will go into the same shard.

This will get us pretty far, but means that dashboard queries must aggregate every row
in the target time range for every query it answers... pretty slow! It also means that
storage costs will grow proportionately with the ingest rate and length of queryable
history.

In order to fix both problems, we'll introduce :ref:`rollups <rollups>`. The raw data
will be aggregated into other tables which store the same data in 1-minute, 1-hour, and
1-day intervals. These correspond to zoom-levels in the dashboard. When the user wants
request times for the last month the dashboard can read and chart the values for the last
30 days.
 
Queries
-------

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

We've included :ref:`a section <approx_dist_count>` which showcases their usage with
Citus.

JSONB
-----

Citus works well with Postgres' built-in support for JSON data types.

- We have `a blog post
  <https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`_
  explaining which format to use for your semi-structured data. It says you should
  usually use jsonb but never says how. A section here will go over an example usage of
  JSONB.

