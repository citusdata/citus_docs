.. _introduction:

Real Time Analytics
#####################

Over the last few years we've helped many different kinds of clients use Citus and noticed
a technical problem many businesses have: running real-time analytics over large streams
of data.

For example, say you're building and selling an HTTP analytics dashboard. Your business is
proving pretty popular, so your users' sites generate 1000 requests every second. You want
to ingest all of those records (1000 inserts/sec) and create a dashboard which shows your
users things like how many requests to their sites are errors. It's important that this
data shows up with as little latency as possible so your clients can fix problems with
their sites. It's also useful to show graphs of historical data, however keeping all the
raw data around forever is prohibitively expensive.

Alternatively, maybe you're building an advertising network and want to show clients
clickthrough rates on their campaigns. In this example latency is also critical, raw data
volume is also high, and both historical and live data are important.

In this reference architecture we'll demonstrate how to build part of the first example,
but this architecture would work equally well for the second and many other business
use-cases.

Running It Yourself
-------------------

There's `a github repo <https://github.com/citusdata/reference-architecture-resources>`_
with scripts and usage instructions. If you've gone through our installation instructions
and have Citus running, whether on a single machine or multiple machines, you're ready to
try it out. There will be code snippets in this tutorial but they don't quite specify a
complete system. The github repo has all the details in one place.

Data Model
----------

The data we're dealing with is an immutable stream of log data. In this example we'll
insert directly into Citus but it's also common for this data to first be routed through
something like Kafka. Doing so has the usual advantages, and makes it easier to
pre-aggregate the data once data volumes vecome unmanageably high.

In this example, the raw data will use the following schema which isn't very realistic as
far as http analytics go but sufficient for showing off the architecture we have in mind.

.. code-block:: sql

  -- this is run on the master
  CREATE TABLE http_request (
    zone_id INT, -- every customer's site is a different "zone"
    ingest_time TIMESTAMPTZ DEFAULT now(),

    session_id UUID,
    url TEXT,
    request_country TEXT,
    ip_address INET,

    status_code INT,
    response_time_msec INT
  );
  SELECT master_create_distributed_table('http_request', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_request', 16, 2);

When we call :ref:`master_create_distributed_table <master_create_distributed_table>`
we ask Citus to hash-distribute ``http_request`` using the ``zone_id`` column. That means
that, since the dashboard only looks at a single zone, all dashboard queries will hit a
single shard.

When we call :ref:`master_create_worker_shards <master_create_worker_shards>` we tell
Citus to create 16 shards, and 2 replicas of each shard (for a total of 32 shard
replicas).  :ref:`We recommend <faq_choose_shard_count>` using 2-4x as many shards as
cores in your cluster. If you use at least as many shards as cores, any queries you run
across the entire dataset will run in parallel and take advantage of all your workers. If
you use 2-4x as many shards, you make it easy to add workers later, but don't add much
additional overhead.

Using a replication factor of 2 (or any number greater than 1, really) means every row is
written to multiple workers. When a worker fails the master will serve queries for any
shards that worker was responsible for by querying the other replicas so you don't have
any downtime.

.. NOTE::

  In Citus Cloud you must use a replication factor of 1 (instead of the 2 used here). As
  Citus Cloud uses `streaming replication
  <https://www.postgresql.org/docs/current/static/warm-standby.html>`_ to achieve high
  availability maintaining shard replicas would be redundant.

With this, the system is ready to accept data and serve queries! You can run
queries such as:

.. code-block:: sql

  INSERT INTO http_request (
      zone_id, session_id, url, request_country,
      ip_address, status_code, response_time_msec
  ) VALUES (
      1, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'http://example.com/path', 'USA',
      cidr '88.250.10.123', 200, 10
  );

And do some dashboard queries like:

.. code-block:: sql

  SELECT
    date_trunc('minute', ingest_time) as minute,
    COUNT(1) AS request_count,

    SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,

    SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
  FROM http_request
  WHERE zone_id = 1 AND minute > date_trunc('minute', now()) - interval '5 minutes'
  GROUP BY minute;

We've provided `a data ingest script <http://github.com>`_ you can run to generate example
data.

The above setup will get you pretty far, but has a few drawbacks:

* The dashboard must aggregate every row in the target date range for every query it
  answers.
* Storage costs will grow proportionally with the ingest rate and the length of the
  queryable history.

Rollups
-------

In order to fix both problems, we have multiple clients who roll up the raw data into a
pre-aggregated form. Here, we'll aggregate the raw data into a table which stores
summaries of 1-minute intervals. In a production system, you would probably also want
something like 1-hour and 1-day intervals, these each correspond to zoom-levels in the
dashboard. When the user wants request times for the last month the dashboard can simply
read and chart the values for each of the last 30 days, no aggregation required.

.. code-block:: sql

  CREATE TABLE http_request_1min (
        zone_id INT,
        ingest_time TIMESTAMPTZ, -- which minute this row represents

        error_count INT,
        success_count INT,
        request_count INT,
        average_response_time_msec INT,
        CHECK (request_count = error_count + success_count)
  );
  SELECT master_create_distributed_table('http_requests_1min', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests_1min', 16, 2);
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX ON http_requests_1min (zone_id, ingest_time);

This looks a lot like the previous code block. Most importantly: It also shards on
``zone_id``, and it also uses 16 shards with 2 replicas of each. Because all three of
those match, there's a 1-to-1 correspondence between ``http_request`` shards and
``http_request_1min`` shards, and Citus will place matching shards on the same worker.
This is called colocation; it makes queries such as joins faster and our rollups possible.

.. image:: /images/colocation.png
  :alt: colocation in citus

In order to populate ``http_request_1min`` we're going to periodically run the equivalent
of an INSERT INTO SELECT. Citus doesn't yet support INSERT INTO SELECT on distributed
tables, so instead we'll run a function on all the workers which runs INSERT INTO SELECT
on every matching pair of shards. This is possible because the shards are colocated: a
function running on a worker will always be able to access both the shard of raw data and
the matching shard of aggregated data that it needs.

.. code-block:: plpgsql

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
          zone_id, ingest_time, request_count,
          error_count, success_count, average_response_time_msec
        ) SELECT
          zone_id,
          date_trunc('minute', ingest_time) as minute,
          COUNT(1) as request_count,
          SUM(CASE WHEN (status_code between 200 and 299) THEN 1 ELSE 0 END) as success_count,
          SUM(CASE WHEN (status_code between 200 and 299) THEN 0 ELSE 1 END) as error_count,
          SUM(response_time_msec) / COUNT(1) AS average_response_time_msec
        FROM %1$I
        WHERE
          date_trunc('minute', ingest_time) > (SELECT max(ingest_time) FROM %2$I)
          AND date_trunc('minute', ingest_time) < date_trunc('minute', now())
        GROUP BY zone_id, minute
        ORDER BY minute ASC;
      $insert$, p_source_shard, p_dest_shard);
    END;
    $$ LANGUAGE 'plpgsql';

Inside this function you can see the dashboard query from earlier. It's been wrapped in
some machinery which writes the results into ``http_request_1min`` and allows passing in
the name of the shards to read and write from. It also takes out an advisory lock, to
ensure there aren't any concurrency bugs where the same rows are written multiple times.

The machinery above which accepts the names of the shards to read and write is necessary
because only the master has the metadata required to know what the shard pairs are. It has
its own function to figure that out:

.. code-block:: plpgsql

    CREATE FUNCTION colocated_shard_placements(left_table REGCLASS, right_table REGCLASS)
    RETURNS TABLE (left_shard TEXT, right_shard TEXT, nodename TEXT, nodeport BIGINT) AS $$
      SELECT
        a.logicalrelid::regclass||'_'||a.shardid,
        b.logicalrelid::regclass||'_'||b.shardid,
        nodename, nodeport
      FROM pg_dist_shard a
      JOIN pg_dist_shard b USING (shardminvalue)
      JOIN pg_dist_shard_placement p ON (a.shardid = p.shardid)
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
  master, and assuming you named the above script ``run_rollups.sh``, you can do something
  as simple as this:

  .. code-block:: bash
  
     * * * * * /some/path/run_rollups.sh

The dashboard query from earlier is now a lot nicer:

.. code-block:: sql

  SELECT
    request_count, success_count, error_count, average_response_time_msec
  FROM http_request_1min
  WHERE zone_id = 1 AND minute > date_trunc('minute', now()) - interval '5 minutes';

Expiring Old Data
-----------------

The rollups make queries faster but we still have a lot of raw data sitting around. How
long you should keep each granularity of data is a business decision, but once you decide
it's easy to write a function to expire old data:

.. code-block:: plpgsql

  -- another function for the master
  CREATE FUNCTION expire_old_request_data() RETURNS void
  AS $$
    SET LOCAL citus.all_modification_commutative TO TRUE;
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request WHERE ingest_time < now() - interval ''1 hour'';');
    SELECT master_modify_multiple_shards(
      'DELETE FROM http_request_1min WHERE ingest_time < now() - interval ''1 day'';');
  END;
  $$ LANGUAGE 'sql';

.. NOTE::

  The above function should be called every minute. As mentioned above there are many
  different ways to accomplish this and no way which makes everybody happy. If you're
  capable of adding cron entries to the machine the master is running on you might
  consider adding a crontab entry:

  .. code-block:: bash
  
    * * * * * psql -c "SELECT expire_old_request_data();"

Review, what have we done?
--------------------------

That's the entire architecture! The next few sections are solutions to additional problems
which often pop up. So what makes the rollups better than using raw data? Let's look again
at the problem it solves. We wanted to enable a dashboard which aggregated:

1. Large amounts of data
2. Low latency

Where the naive solution struggled with a few problems:

A. The dashboard must aggregate every row in the target date range for every query it
   answers.
B. Storage costs will grow proportionally with the ingest rate and the length of the
   queryable history.

Because we roll up the raw data, and the dashboard only runs queries on that raw data, it
must do a constant amount of work for each user. Users who have much more visiters than
average won't have a dashboard which works any slower. Because the rollups fire every
minute,

If you've heard of postgres' VACUUM, you know it can be a pain once you have a large
number of rows. The write pattern we're using turns out to be the ideal VACUUM use-case.
We never modify rows, we only write to one end of the table while deleting from the other
end. When VACUUM runs it marks a `visibility map
<https://www.postgresql.org/docs/9.5/static/storage-vm.html>`_ to keep track of which
pages have already been vacuumed and can be skipped during the next vacuum. Since we never
UPDATE, the only pages which have that bit reset are the pages of entirely DELETEd rows.
All VACUUM needs to do is scan through and reclaim those empty pages, it happens very
quickly!

Approximate Distinct Counts
---------------------------

A common question in http analytics deals with :ref:`approximate distinct counts
<count_distinct>`: How many unique visitors visited your site over some time period?
Answering it exactly requires storing the list of all previously-seen visitors in the
rollup tables, a prohibitively large amount of data. A datatype called hyperloglog, or
HLL, can answer the query approximately; it takes a surprisingly small amount of space to
tell you approximately how many unique elements are in a set you pass it. Its accuracy can
be adjusted, we'll use ones which, using only 1280 bytes, will be able to count up to tens
of billions of unique visitors with at most 2.2% error.

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

Where the HLL extension provides distinct counts, there are a more extensions which do
a similar thing (improve performance and storage requirements) for other kinds of queries,
such as `count-min sketch <https://github.com/citusdata/cms_topn>`_ for top-n queries, and
`HDR <https://github.com/citusdata/HDR>`_, for percentile queries.

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

Resources
---------

That's everything we wanted to cover. This article has been a little more in-depth than
the rest of our documentation, but it shows a complete system to give you an idea of what
building a non-trivial application with Citus looks like. We hope it helps you figure out
how to use Citus for your specific use-case. Have we mentioned there's `a github repo
<https://github.com/citusdata/reference-architecture-resources>`_ with lots of resources?
