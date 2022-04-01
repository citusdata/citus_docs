.. _article_hll_count:

Distributed Distinct Count with HyperLogLog on Postgres
=======================================================

(Copy of `original publication <https://www.citusdata.com/blog/2017/04/04/distributed_count_distinct_with_postgresql/>`__)

Running ``SELECT COUNT(DISTINCT)`` on your database is all too common.
In applications it's typical to have some analytics dashboard
highlighting the number of unique items such as unique users, unique
products, unique visits. While traditional ``SELECT COUNT(DISTINCT)``
queries works well in single machine setups, it is a difficult problem
to solve in distributed systems. When you have this type of query, you
can't just push query to the workers and add up results, because most
likely there will be overlapping records in different workers. Instead
you can do:

-  Pull all distinct data to one machine and count there. (Doesn't
   scale)
-  Do a map/reduce. (Scales but it's very slow)

This is where approximation algorithms or sketches come in. Sketches are
probabilistic algorithms which can generate approximate results
efficiently within mathematically provable error bounds. There are a
many of them out there, but today we're just going to focus on one,
HyperLogLog or
`HLL <https://github.com/aggregateknowledge/postgresql-hll>`__. HLL is
very successfull for estimating unique number of elements in a list.
First we'll look some at the internals of the HLL to help us understand
why HLL algorithm is useful to solve distict count problem in a scalable
way, then how it can be applied in a distributed fashion. Then we will
see some examples of HLL usage.

What does HLL do behind the curtains?
-------------------------------------

Hash all elements
~~~~~~~~~~~~~~~~~

HLL and almost all other probabilistic counting algorithms depend on
uniform distribution of the data. Since in the real world, our data is
generally not distributed uniformly, HLL firsts hashes each element to
make the data distribution more uniform. Here, by uniform distribution,
we mean that each bit of the element has 0.5 probability of being 0 or
1. We will see why this is useful in couple of minutes. Apart from
uniformity, hashing allows HLL to treat all data types same. As long as
you have a hash function for your data type, you can use HLL for
cardinality estimation.

Observe the data for rare patterns
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After hashing all the elements, HLL looks for the binary representation
of each hashed element. It mainly looks if there are bit patterns which
are less likely to occur. Existence of such rare patterns means that we
are dealing with large dataset.

For this purpose, HLL looks number of leading zero bits in the hash
value of each element and finds maximum number of leading zero bits.
Basically, to be able to observe k leading zeros, we need 2k+1 trials
(i.e. hashed numbers). Therefore, if maximum number of leading zeros is
k in a data set, HLL concludes that there are approximately 2k+1
distinct elements.

This is pretty straightforward and simple estimation method. However; it
has some important properties, which are especially shine in distributed
environment;

-  HLL has very low memory footprint. For maximum number n, we need to
   store just *log log n* bits. For example; if we hash our elements
   into 64 bit integers, we just need to store 6 bits to make an
   estimation. This saves a lot of memory especially compared with naive
   approach where we need to remember all the values.
-  We only need to do one pass on the data to find maximum number of
   leading zeros.
-  We can work with streaming data. After calculating maximum number of
   leading zeros, if some new data arrives we can include them into
   calculation without going over whole data set. We only need to find
   number of leading zeros of each new element, compare them with
   maximum number of leading zeros of whole dataset and update maximum
   number of leading zeros if necessary.
-  We can merge estimations of two separate datasets efficiently. We
   only need to pick bigger number of leading zeros as maximum number of
   leading zeros of combined dataset. This allow us to separate the data
   into shards, estimate their cardinality and merge the results. This
   is called additivity and it allow us to use HLL in distributed
   systems.

Stochastic Averaging
~~~~~~~~~~~~~~~~~~~~

If you think above is not that good estimation, you are right. First of
all, our prediction is always in the form of 2k. Secondly we may end up
with pretty far estimates if the data distribution is not uniform
enough.

One possible fix for these problems could be just repeating the process
with different hash functions and taking the average, which would work
fine but hashing all the data multiple times is expensive. HLL fixes
this problem something called stochastic averaging. Basically, we divide
our data into buckets and use aforementioned algorithm for each bucket
separately. Then we just take the average of the results. We use first
few bits of the hash value to determine which bucket a particular
element belongs to and use remaining bits to calculate maximum number of
leading zeros.

Moreover, we can configure precision by choosing number of buckets to
divide the data. We will need to store *log log n* bits for each bucket.
Since we can store each estimation in *log log n* bits, we can create
lots of buckets and still end up using insignificant amount of memory.
Having such small memory footprint is especially important while
operating on large scale data. To merge two estimations, we will merge
each bucket then take the average. Therefore, if we plan to do merge
operation, we should keep each bucket's maximum number of leading zeros.

More?
~~~~~

HLL does some other things too to increase accuracy of the estimation,
however observing bit patterns and stochastic averaging is the key
points of HLL. After these optimizations, HLL can estimate cardinality
of a dataset with typical error rate 2% error rate using 1.5 kB of
memory. Of course is is possible to increase accuracy by using more
memory. We will not go into details of other steps but there are tons of
content on the internet about HLL.

HLL in distributed systems
--------------------------

As we mentioned, HLL has additivity property. This means you can divide
your dataset into several parts, operate on them with HLL algorithm to
find unique element count of each part. Then you can merge intermediate
HLL results efficiently to find unique element count of all data without
looking back to original data.

If you work on large scale data and you keep parts of your data in
different physical machines, you can use HLL to calculate unique count
over all your data without pulling whole data to one place. In fact,
Citus can do this operation for you. There is a `HLL
extension <https://github.com/aggregateknowledge/postgresql-hll>`__
developed for PostgreSQL and it is fully compatible with Citus. If you
have HLL extension installed and want to run COUNT(DISTINCT) query on a
distributed table, Citus automatically uses HLL. You do not need to do
anything extra once you configured it.

Hands on with HLL
-----------------

.. NOTE::

   This section mentions the Citus Cloud service.  We are no longer onboarding
   new users to Citus Cloud on AWS. If you’re new to Citus, the good news is,
   Citus is still available to you: as open source, and in the cloud on
   Microsoft Azure, as a fully-integrated deployment option in Azure Database
   for PostgreSQL.

   See :ref:`cloud_topic`.

Setup
~~~~~

To play with HLL we will use Citus Cloud and GitHub events data. You can
see and learn more about Citus Cloud and this data set from
`here <https://www.citusdata.com/blog/2017/01/27/getting-started-with-github-events-data/>`__.
Assuming you created your Citus Cloud instance and connected it via
psql, you can create HLL extension by simply running the below command from the coordinator;

.. code:: sql

    CREATE EXTENSION hll;

Then enable count distinct approximations by setting the
*citus.count\_distinct\_error\_rate* configuration value. Lower values
for this configuration setting are expected to give more accurate
results but take more time and use more memory for computation. We
recommend setting this to 0.005.

.. code:: sql

    SET citus.count_distinct_error_rate TO 0.005;

Different from `previous blog
post <https://www.citusdata.com/blog/2017/01/27/getting-started-with-github-events-data/>`__,
we will only use github\_events table and we will use
`large\_events.csv <https://examples.citusdata.com/large_events.csv>`__
data set;

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

    SELECT create_distributed_table('github_events', 'user_id');

    \COPY github_events FROM large_events.csv CSV

Examples
~~~~~~~~

After distributing the table, we can use regular COUNT(DISTINCT) query
to find out how many unique users created an event;

.. code:: sql

    SELECT
        COUNT(DISTINCT user_id)
    FROM
        github_events;

It should return something like this;

::

    .
     count
    --------
     264227
    
    (1 row)

It looks like this query does not have anything with HLL. However if you
set *citus.count\_distinct\_error\_rate* to something bigger than 0 and
issue COUNT(DISTINCT) query; Citus automatically uses HLL. For simple
use-cases like this, you don’t even need to change your queries. Exact
distinct count of users who created an event is 264198, so our error
rate is little bigger than 0.0001.

We can also use constraints to filter out some results. For example we
can query number of unique users who created a PushEvent;

.. code:: sql

    SELECT
        COUNT(DISTINCT user_id)
    FROM
        github_events
    WHERE
        event_type = 'PushEvent'::text;

It would return;

::

    .
     count
    --------
     157471
    
    (1 row)

Similarly exact distinct count for this query is 157154 and our error
rate is little bigger than 0.002.

Conclusion
~~~~~~~~~~

If you're having trouble scaling ``count (distinct)`` in Postgres give
HLL a look it may be useful if close enough counts ares feasible for
you.
