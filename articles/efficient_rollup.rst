Efficient Rollup Tables with HyperLogLog in Postgres
====================================================

(Copy of `original publication <https://www.citusdata.com/blog/2017/06/30/efficient-rollup-with-hyperloglog-on-postgres/>`__)


Rollup tables are commonly used in Postgres when you don’t need to
perform detailed analysis, but you still need to answer basic
aggregation queries on older data.

With rollup tables, you can pre-aggregate your older data for the
queries you still need to answer. Then you no longer need to store all
of the older data, rather, you can delete the older data or roll it off
to slower storage—saving space and computing power.

Let’s walk through a rollup table example in Postgres without using HLL.

Rollup tables without HLL—using GitHub events data as an example
----------------------------------------------------------------

For this example we will create a rollup table that aggregates
historical data: `a GitHub events data
set <https://examples.citusdata.com/events.csv>`__.

Each record in this GitHub data set represents an event created in
GitHub, along with key information regarding the event such as event
type, creation date, and the user who created the event. (Craig
Kerstiens has written about this same data set in the past, in his
`getting started with GitHub event data on Citus
<https://www.citusdata.com/blog/2017/01/27/getting-started-with-github-events-data/>`__
post.)

If you want to create a chart to show the number of GitHub event
creations in each minute, a rollup table would be super useful. With a
rollup table, you won’t need to store all user events in order to create
the chart. Rather, you can aggregate the number of event creations for
each minute and just store the aggregated data. You can then throw away
the rest of the events data, if you are trying to conserve space.

To illustrate the example above, let's create ``github_events`` table
and load data to the table:

.. code:: psql

    CREATE TABLE github_events
    (
        event_id bigint,
        event_type text,
        event_public boolean,
        repo_id bigint,
        payload jsonb,
        repo jsonb,
        user_id bigint,
        org jsonb,
        created_at timestamp 
    );

    \COPY github_events FROM events.csv CSV

In this example, I’m assuming you probably won’t perform detailed
analysis on your older data on a regular basis. So there is no need to
allocate resources for the older data, instead you can use rollup tables
and just keep the necessary information in memory. You can create a
rollup table for this purpose:

.. code:: sql

    CREATE TABLE github_events_rollup_minute
    (
        created_at timestamp,
        event_count bigint
    );

And populate with INSERT/SELECT:

.. code:: sql

    INSERT INTO github_events_rollup_minute(
        created_at,
        event_count
    )
    SELECT
        date_trunc('minute', created_at) AS created_at,
        COUNT(*) AS event_count
    FROM github_events
    GROUP BY 1;

Now you can store the older (and bigger) data in a less expensive
resource like disk so that you can access it in the future—and keep the
``github_events_rollup_minute`` table in memory so you can create your
analytics dashboard.

By aggregating the data by minute in the example above, you can answer
queries like hourly and daily total event creations, but unfortunately
it is not possible to know the more granular event creation count for
each second.

Further, since you did not keep event creations for each user separately
(at least not in this example), you cannot have a separate analysis for
each user with this rollup table. All off these are trade-offs.

Without HLL, rollup tables have a few limitations
-------------------------------------------------

For queries involving distinct count, rollup tables are less useful. For
example, if you pre-aggregate over minutes, you cannot answer queries
asking for distinct counts over an hour. You cannot add each minute’s
result to have hourly event creations by unique users. Why? Because you
are likely to have overlapping records in different minutes.

And if you want to calculate distinct counts constrained by combinations
of columns, you would need multiple rollup tables.

Sometimes you want to get event creation count by unique users filtered
by date and sometimes you want to get unique event creation counts
filtered by event type (and sometimes a combination of both.) With HLL,
one rollup table can answer all of these queries—but without HLL, you
would need a separate rollup table for each of these different types of
queries.

HLL to the rescue
-----------------

If you do rollups with the HLL data type (instead of rolling up the
final unique user count), you can easily overcome the overlapping
records problem. HLL encodes the data in a way that allows summing up
individual unique counts without re-counting overlapping records.

HLL is also useful if you want to calculate distinct counts constrained
by combinations of columns. For example, if you want to get unique event
creation counts per date and/or per event type, with HLL, you can use
just one rollup table for all combinations.

Whereas without HLL, if you want to calculate distinct counts
constrained by combinations of columns, you would need to create:

-  7 different rollup tables to cover all combinations of 3 columns
-  15 rollup tables to cover all combinations of 4 columns
-  2n - 1 rollup tables to cover all combinations in n columns

HLL and rollup tables in action, together
-----------------------------------------

Let's see how HLL can help us to answer some typical distinct count
queries on GitHub events data. If you did not create a ``github_events``
table in the previous example, create and populate it now with the
`GitHub events data set <https://examples.citusdata.com/events.csv>`__:

.. code:: psql

    CREATE TABLE github_events
    (
        event_id bigint,
        event_type text,
        event_public boolean,
        repo_id bigint,
        payload jsonb,
        repo jsonb,
        user_id bigint,
        org jsonb,
        created_at timestamp
    );

    \COPY github_events FROM events.csv CSV

After creating your table, let’s also create a rollup table. We want to
get distinct counts both per ``user`` and per ``event_type`` basis.
Therefore you should use a slightly different rollup table:

.. code:: sql

    DROP TABLE IF EXISTS github_events_rollup_minute;

    CREATE TABLE github_events_rollup_minute(
        created_at timestamp,
        event_type text,
        distinct_user_id_count hll
    );

Finally, you can use INSERT/SELECT to populate your rollup table and you
can use ``hll_hash_bigint`` function to hash each ``user_id``. (For an
explanation of why you need to hash elements, be sure to read our Citus
blog post on `distributed counts with HyperLogLog on
Postgres <https://www.citusdata.com/blog/2017/04/04/distributed_count_distinct_with_postgresql/>`__):

.. code:: sql

    INSERT INTO github_events_rollup_minute(
        created_at,
        event_type,
        distinct_user_id_count
    )
    SELECT
        date_trunc('minute', created_at) AS created_at,
        event_type,
        sum(hll_hash_bigint(user_id))
    FROM github_events
    GROUP BY 1, 2;

    INSERT 0 2484

What kinds of queries can HLL answer?
-------------------------------------

Let’s start with a simple case to see how to materialize HLL values to
actual distinct counts. To demonstrate that, we will answer the
question:

**How many distinct users created an event for each event type at each
minute at 2016-12-01 05:35:00?**

We will just need to use the ``hll_cardinality`` function to materialize
the HLL data structures to actual distinct count.

.. code:: sql

    SELECT
        created_at,
        event_type,
        hll_cardinality(distinct_user_id_count) AS distinct_count
    FROM
        github_events_rollup_minute
    WHERE
        created_at = '2016-12-01 05:35:00'::timestamp
    ORDER BY 2;

         created_at      |          event_type           |  distinct_count  
    ---------------------+-------------------------------+------------------
     2016-12-01 05:35:00 | CommitCommentEvent            |                1
     2016-12-01 05:35:00 | CreateEvent                   |               59
     2016-12-01 05:35:00 | DeleteEvent                   |                6
     2016-12-01 05:35:00 | ForkEvent                     |               20
     2016-12-01 05:35:00 | GollumEvent                   |                2
     2016-12-01 05:35:00 | IssueCommentEvent             |               42
     2016-12-01 05:35:00 | IssuesEvent                   |               13
     2016-12-01 05:35:00 | MemberEvent                   |                4
     2016-12-01 05:35:00 | PullRequestEvent              |               24
     2016-12-01 05:35:00 | PullRequestReviewCommentEvent |                4
     2016-12-01 05:35:00 | PushEvent                     | 254.135297564883
     2016-12-01 05:35:00 | ReleaseEvent                  |                4
     2016-12-01 05:35:00 | WatchEvent                    |               57
    (13 rows)

Then let’s continue with a query which we could not answer without HLL:

**How many distinct users created an event during this one-hour
period?**

With HLLs, this is easy to answer.

.. code:: sql

    SELECT
        hll_cardinality(SUM(distinct_user_id_count)) AS distinct_count
    FROM
        github_events_rollup_minute
    WHERE
        created_at BETWEEN '2016-12-01 05:00:00'::timestamp AND '2016-12-01 06:00:00'::timestamp;


     distinct_count  
    ------------------
     10978.2523520687
    (1 row)

Another question where we can use HLL’s additivity property to answer
would be:

**How many unique users created an event during each hour at
2016-12-01?**

.. code:: sql

    SELECT
        EXTRACT(HOUR FROM created_at) AS hour,
        hll_cardinality(SUM(distinct_user_id_count)) AS distinct_count
    FROM
        github_events_rollup_minute
    WHERE
        created_at BETWEEN '2016-12-01 00:00:00'::timestamp AND '2016-12-01 23:59:59'::timestamp
    GROUP BY 1
    ORDER BY 1;

      hour |  distinct_count
    -------+------------------
         5 |  10598.637184899
         6 | 17343.2846931687
         7 | 18182.5699816622
         8 | 12663.9497604266
    (4 rows)

Since our data is limited, the query only returned 4 rows, but that is
not the point of course. Finally, let's answer a final question:

**How many distinct users created a PushEvent during each hour?**

.. code:: sql

    SELECT
        EXTRACT(HOUR FROM created_at) AS hour,
        hll_cardinality(SUM(distinct_user_id_count)) AS distinct_push_count
    FROM
        github_events_rollup_minute
    WHERE
        created_at BETWEEN '2016-12-01 00:00:00'::timestamp AND '2016-12-01 23:59:59'::timestamp
        AND event_type = 'PushEvent'::text
    GROUP BY 1
    ORDER BY 1;


     hour | distinct_push_count 
    ------+---------------------
        5 |    6206.61586498546
        6 |    9517.80542100396
        7 |    10370.4087640166
        8 |    7067.26073810357
    (4 rows)

A rollup table with HLL is worth a thousand rollup tables without HLL
---------------------------------------------------------------------

Yes, I believe a rollup table with HLL is worth a thousand rollup tables
without HLL.

Well, maybe not a thousand, but it is true that one rollup table with
HLL can answer lots of queries where otherwise you would need a
different rollup table for each query. Above, we demonstrated that with
HLL, 4 example queries all can be answered with a single rollup table—
and without HLL, we would have needed 3 separate rollup tables to answer
all these queries.

In the real world, if you do not take advantage of HLL you are likely to
need even more rollup tables to support your analytics queries.
Basically for all combinations of n constraints, you would need 2n - 1
rollup tables whereas with HLL just one rollup table can do the job.

One rollup table (with HLL) is obviously much easier to maintain than
multiple rollup tables. And that one rollup table uses significantly
less memory too. In some cases, without HLL, the overhead of using
rollup tables can become too expensive and exceeds the benefit of using
rollup tables, so people decide not to use rollup tables at all.

Want to learn more about HLL in Postgres?
-----------------------------------------

HLL is not only useful to create rollup tables, HLL is useful in
distributed systems, too. Just as with rollup tables, in a distributed
system, such as Citus, we often place different parts of our
data in different nodes, hence we are likely to have overlapping records
at different nodes. Thus, the clever techniques HLL uses to encode data
to merge separate unique counts (and address the overlapping record
problem) can also help in distributed systems.

If you want to learn more about HLL, read :ref:`how HLL can be used in
distributed systems <article_hll_count>`,
where we explained the internals of HLL and how HLL merges separate
unique counts without counting overlapping records.
