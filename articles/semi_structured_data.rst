.. _semi_structured_sharding:

Sharding Postgres with Semi-Structured Data and Its Performance Implications
############################################################################

(Copy of `original publication <https://www.citusdata.com/blog/2016/07/25/sharding-json-in-postgres-and-performance/>`__)

If you're looking at Citus its likely you've outgrown a single node
database. In most cases your application is no longer performing
as you’d like.  In cases where your data is still under 100 GB a
single Postgres instance will still work well for you, and is a great
choice. At levels beyond that Citus can help, but how you model your
data has a major impact on how much performance you're able to get out
of the system.

Some applications fit naturally in this scaled out model, but others
require changes in your application. The model you choose can determine
the queries you’ll be able to run in a performant manner. You can
approach this in two ways either from how your data may already be
modeled today or more ideally by examining the queries you’re looking to
run and needs on performance of them to inform which data model may make
the most sense.

One large table, without joins
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

We've found that storing semi-structured data in JSONB helps reduce the
number of tables required, which improves scalability. Let’s look at the
example of web analytics data. They traditionally store a table of
events with minimal information, and use lookup tables to refer to the
events and record extra information. Some events have more associated
information than others. By replacing the lookup tables by a JSONB
column you can easily query and filter while still having great
performance. Let’s take a look at what an example schema might look like
following by a few queries to show what’s possible:

.. code:: sql

    CREATE TABLE visits AS (
      id UUID,
      site_id uuid,
      visited_at TIMESTAMPTZ,
      session_id UUID,
      page TEXT,
      url_params JSONB
    )

Note that url parameters for an event are open-ended, and no parameters
are guaranteed. Even the common "utm" parameters (such as utm\_source,
utm\_medium, utm\_campaign) are by no means universal. Our choice of
using a
`JSONB <https://www.citusdata.com/blog/2016/07/14/choosing-nosql-hstore-json-jsonb/>`__
column for url\_params is much more convenient than creating columns for
each parameter. With JSONB we can get both the flexibility of schema,
and combined with `GIN
indexing <https://www.postgresql.org/docs/10/static/gin.html>`__ we can
still have performant queries against all keys and values without having
to index them individually.

Enter Citus
~~~~~~~~~~~

Assuming you do need to scale beyond a single node,
`Citus <https://www.citusdata.com/product/>`__ can help at scaling out
your processing power, memory, and storage. In the early stages of
utilizing Citus you’ll create your schema, then tell the system how you
wish to shard your data.

In order to determine the ideal sharding key you need to examine the
query load and types of operations you’re looking to perform. If you are
storing aggregated data and all of your queries are per customer then a
shard key such as customer\_id or tenant\_id can be a great choice. Even
if you have minutely rollups and then need to report on a daily basis
this can work well. This allows you to easily route queries to shards
just for that customer. As a result of routing queries to a single shard
this can allow you a higher concurrency.

In the case where you are storing raw data, there often ends up being a
lot of data per customer. Here it can be more difficult to get
sub-second response without further parallelizing queries per customer.
*It may also be difficult to get predictable sub-second responsiveness
if you have a low number of customers or if 80% of your data comes from
one customer.* In the above mentioned cases, picking a shard key that's
more granular than customer or tenant id can be ideal.

The distribution of your data and query workload is what will heavily
determine which key is right for you.

With the above example if all of your sites have the same amount of
traffic then ``site_id`` might be reasonable, but if either of the above
cases is true then something like ``session_id`` could be a more ideal
distribution key.

The query workload
~~~~~~~~~~~~~~~~~~

With a sharding key of ``session_id`` we could easily perform a number
of queries such as:

Top page views over the last 7 days for a given site:

.. code:: sql

    SELECT page,
           count(*)
    FROM visits
    WHERE site_id = 'foo'
      AND visited_at > now() - '7 days'::interval
    GROUP BY page
    ORDER BY 2 DESC;

Unique sessions today:

.. code:: sql

    SELECT distinct(session_id)
    FROM visits
    WHERE site_id = 'foo'
      AND visited_at > date_trunc('date', now())

And assuming you have an index on ``url_params`` you could easily do
various rollups on it… Such as find the campaigns that have driven the
most traffic to you over the past 30 days and which pages received the
most benefit:

.. code:: sql

    SELECT url_params ->> 'utm_campaign',
           page,
           count(*)
    FROM visits
    WHERE url_params ? 'utm_campaign'
      AND visited_at >= now() - '30 days'::interval
      AND site_id = 'foo'
    GROUP BY url_params ->> 'utm_campaign',
             page
    ORDER BY 3 DESC;

Every distribution has its thorns
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Choosing a sharding key always involves trade-offs. If you’re optimising
to get the maximum parallelism out of your database then matching your
cores to the number of shards ensures that every query takes full
advantage of your resources. In contrast if you’re optimising for higher
read concurrency, then allowing queries to run against only a single
shard will allow more queries to run at once, although each individual
query will experience less parallelism.

The choice really comes down to what you’re trying to accomplish in your
application. If you have questions about what method to use to shard
your data, or what key makes sense for your application please feel free
to reach out to us or join our slack channel.
