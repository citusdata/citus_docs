.. _querying:

Querying Distributed Tables (SQL)
=================================

As discussed in the previous sections, Citus is an extension which extends the latest PostgreSQL for distributed execution. This means that you can use standard PostgreSQL `SELECT <http://www.postgresql.org/docs/current/static/sql-select.html>`_ queries on the Citus coordinator for querying. Citus will then parallelize the SELECT queries involving complex selections, groupings and orderings, and JOINs to speed up the query performance. At a high level, Citus partitions the SELECT query into smaller query fragments, assigns these query fragments to workers, oversees their execution, merges their results (and orders them if needed), and returns the final result to the user.

In the following sections, we discuss the different types of queries you can run using Citus.

.. _aggregate_functions:

Aggregate Functions
-------------------

Citus supports and parallelizes most aggregate functions supported by
PostgreSQL, including custom user-defined aggregates. Aggregates execute using
one of three methods, in this order of preference:

1. When the aggregate is grouped by a table's distribution column, Citus can
   push down execution of the entire query to each worker. All aggregates are
   supported in this situation and execute in parallel on the worker nodes.
   (Any custom aggregates being used must be installed on the workers.)
2. When the aggregate is *not* grouped by a table's distribution column, Citus
   can still optimize on a case-by-case basis. Citus has internal rules for
   certain aggregates like sum(), avg(), and count(distinct) that allows it to
   rewrite queries for *partial aggregation* on workers. For instance, to
   calculate an average, Citus obtains a sum and a count from each worker,
   and then the coordinator node computes the final average.

   Full list of the special-case aggregates:

     avg, min, max, sum, count, array_agg, jsonb_agg, jsonb_object_agg,
     json_agg, json_object_agg, bit_and, bit_or, bool_and, bool_or,
     every, hll_add_agg, hll_union_agg, topn_add_agg, topn_union_agg,
     any_value, var_pop(float4), var_pop(float8), var_samp(float4),
     var_samp(float8), variance(float4), variance(float8) stddev_pop(float4),
     stddev_pop(float8), stddev_samp(float4), stddev_samp(float8)
     stddev(float4), stddev(float8)
     tdigest(double precision, int), tdigest_percentile(double precision, int, double precision), tdigest_percentile(double precision, int, double precision[]), tdigest_percentile(tdigest, double precision), tdigest_percentile(tdigest, double precision[]), tdigest_percentile_of(double precision, int, double precision), tdigest_percentile_of(double precision, int, double precision[]), tdigest_percentile_of(tdigest, double precision), tdigest_percentile_of(tdigest, double precision[])

3. Last resort: pull all rows from the workers and perform the aggregation on
   the coordinator node. When the aggregate is not grouped on a distribution
   column, and is not one of the predefined special cases, then Citus falls
   back to this approach. It causes network overhead, and can exhaust the
   coordinator's resources if the data set to be aggregated is too large.
   (It's possible to disable this fallback, see below.)

Beware that small changes in a query can change execution modes, causing
potentially surprising inefficiency. For example ``sum(x)`` grouped by a
non-distribution column could use distributed execution, while ``sum(distinct
x)`` has to pull up the entire set of input records to the coordinator.

All it takes is one column to hurt the execution of a whole query. In the
example below, if ``sum(distinct value2)`` has to be grouped on the
coordinator, then so will ``sum(value1)`` even if the latter was fine on its
own.

.. code-block:: sql

  SELECT sum(value1), sum(distinct value2) FROM distributed_table;

To avoid accidentally pulling data to the coordinator, you can set a GUC:

.. code-block:: sql

  SET citus.coordinator_aggregation_strategy TO 'disabled';

Note that disabling the coordinator aggregation strategy will prevent "type
three" aggregate queries from working at all.

.. _count_distinct:

Count (Distinct) Aggregates
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Citus supports count(distinct) aggregates in several ways. If the count(distinct) aggregate is on the distribution column, Citus can directly push down the query to the workers. If not, Citus runs select distinct statements on each worker, and returns the list to the coordinator where it obtains the final count.

Note that transferring this data becomes slower when workers have a greater number of distinct items. This is especially true for queries containing multiple count(distinct) aggregates, e.g.:

.. code-block:: sql

  -- multiple distinct counts in one query tend to be slow
  SELECT count(distinct a), count(distinct b), count(distinct c)
  FROM table_abc;


For these kind of queries, the resulting select distinct statements on the workers essentially produce a cross-product of rows to be transferred to the coordinator.

For increased performance you can choose to make an approximate count instead. Follow the steps below:

1. Download and install the hll extension on all PostgreSQL instances (the coordinator and all the workers).

   Please visit the PostgreSQL hll `github repository <https://github.com/citusdata/postgresql-hll>`_ for specifics on obtaining the extension.

2. Create the hll extension on all the PostgreSQL instances by simply running the below command from the coordinator

  .. code-block:: postgresql

    CREATE EXTENSION hll;

3. Enable count distinct approximations by setting the Citus.count_distinct_error_rate configuration value. Lower values for this configuration setting are expected to give more accurate results but take more time for computation. We recommend setting this to 0.005.

  .. code-block:: postgresql

    SET citus.count_distinct_error_rate to 0.005;

  After this step, count(distinct) aggregates automatically switch to using HLL, with no changes necessary to your queries. You should be able to run approximate count distinct queries on any column of the table.

HyperLogLog Column
$$$$$$$$$$$$$$$$$$

Certain users already store their data as HLL columns. In such cases, they can dynamically roll up those data by calling hll_union_agg(hll_column).

.. _topn:

Estimating Top N Items
~~~~~~~~~~~~~~~~~~~~~~

Calculating the first *n* elements in a set by applying count, sort, and limit is simple. However as data sizes increase, this method becomes slow and resource intensive. It's more efficient to use an approximation.

The open source `TopN extension <https://github.com/citusdata/postgresql-topn>`_ for Postgres enables fast approximate results to "top-n" queries. The extension materializes the top values into a JSON data type. TopN can incrementally update these top values, or merge them on-demand across different time intervals.

**Basic Operations**

Before seeing a realistic example of TopN, let's see how some of its primitive operations work. First ``topn_add`` updates a JSON object with counts of how many times a key has been seen:

.. code-block:: postgres

  -- starting from nothing, record that we saw an "a"
  select topn_add('{}', 'a');
  -- => {"a": 1}

  -- record the sighting of another "a"
  select topn_add(topn_add('{}', 'a'), 'a');
  -- => {"a": 2}

The extension also provides aggregations to scan multiple values:

.. code-block:: postgres

  -- for normal_rand
  create extension tablefunc;

  -- count values from a normal distribution
  SELECT topn_add_agg(floor(abs(i))::text)
    FROM normal_rand(1000, 5, 0.7) i;
  -- => {"2": 1, "3": 74, "4": 420, "5": 425, "6": 77, "7": 3}

If the number of distinct values crosses a threshold, the aggregation drops information for those seen least frequently. This keeps space usage under control. The threshold can be controlled by the ``topn.number_of_counters`` GUC. Its default value is 1000.

**Realistic Example**

Now onto a more realistic example of how TopN works in practice. Let's ingest Amazon product reviews from the year 2000 and use TopN to query it quickly. First download the dataset:

.. code-block:: bash

  curl -L https://examples.citusdata.com/customer_reviews_2000.csv.gz | \
    gunzip > reviews.csv

Next, ingest it into a distributed table:

.. code-block:: psql

  CREATE TABLE customer_reviews
  (
      customer_id TEXT,
      review_date DATE,
      review_rating INTEGER,
      review_votes INTEGER,
      review_helpful_votes INTEGER,
      product_id CHAR(10),
      product_title TEXT,
      product_sales_rank BIGINT,
      product_group TEXT,
      product_category TEXT,
      product_subcategory TEXT,
      similar_product_ids CHAR(10)[]
  );

  SELECT create_distributed_table('customer_reviews', 'product_id');

  \COPY customer_reviews FROM 'reviews.csv' WITH CSV

Next we'll add the extension, create a destination table to store the json data generated by TopN, and apply the ``topn_add_agg`` function we saw previously.

.. code-block:: postgresql

  -- run below command from coordinator, it will be propagated to the worker nodes as well
  CREATE EXTENSION topn;

  -- a table to materialize the daily aggregate
  CREATE TABLE reviews_by_day
  (
    review_date date unique,
    agg_data jsonb
  );

  SELECT create_reference_table('reviews_by_day');

  -- materialize how many reviews each product got per day per customer
  INSERT INTO reviews_by_day
    SELECT review_date, topn_add_agg(product_id)
    FROM customer_reviews
    GROUP BY review_date;

Now, rather than writing a complex window function on ``customer_reviews``, we can simply apply TopN to ``reviews_by_day``. For instance, the following query finds the most frequently reviewed product for each of the first five days:

.. code-block:: postgres

  SELECT review_date, (topn(agg_data, 1)).*
  FROM reviews_by_day
  ORDER BY review_date
  LIMIT 5;

::

  ┌─────────────┬────────────┬───────────┐
  │ review_date │    item    │ frequency │
  ├─────────────┼────────────┼───────────┤
  │ 2000-01-01  │ 0939173344 │        12 │
  │ 2000-01-02  │ B000050XY8 │        11 │
  │ 2000-01-03  │ 0375404368 │        12 │
  │ 2000-01-04  │ 0375408738 │        14 │
  │ 2000-01-05  │ B00000J7J4 │        17 │
  └─────────────┴────────────┴───────────┘


The json fields created by TopN can be merged with ``topn_union`` and ``topn_union_agg``. We can use the latter to merge the data for the entire first month and list the five most reviewed products during that period.

.. code-block:: postgres

  SELECT (topn(topn_union_agg(agg_data), 5)).*
  FROM reviews_by_day
  WHERE review_date >= '2000-01-01' AND review_date < '2000-02-01'
  ORDER BY 2 DESC;

::

  ┌────────────┬───────────┐
  │    item    │ frequency │
  ├────────────┼───────────┤
  │ 0375404368 │       217 │
  │ 0345417623 │       217 │
  │ 0375404376 │       217 │
  │ 0375408738 │       217 │
  │ 043936213X │       204 │
  └────────────┴───────────┘

For more details and examples see the `TopN readme <https://github.com/citusdata/postgresql-topn/blob/master/README.md>`_.

.. _percentile_calculations:

Percentile Calculations
~~~~~~~~~~~~~~~~~~~~~~~

Calculating percentiles over lots of rows might be prohibitively expensive as all rows need to be transferred to the coordinator to find the percentile you are interested in. If an exact percentile is required there is no substitute for this transfer. However if an approximation of the percentile suffices Citus can speed up the query times significantly. Instead of sorting the data to find the percentile it can be run in a single pass over the rows while at the same time only sharing a summary instead of all rows accross the network to the coordinator. Citus has integrated support for the `tdigest extension <https://github.com/tvondra/tdigest>`_ for Postgres.

1. Download and install the tdigest extension on all PostrgeSQL instances (the coordinator and all the workers).

   Please visit the `PostgreSQL tdigest github repository <https://github.com/tvondra/>`_ for specifics on obtaining the extension.

2. Create the tdigest extension on all the PostgreSQL instances by simply rinning the below command from the coordinator

  .. code-block:: postgresql

    CREATE EXTENSION tdigest;

When any of the aggregates defined in the extension is used Citus will rewrite the queries to push down partial tdigest computation to the workers where applicable. This reduces the data sent over the network and removes the requirement for sorting the data.

Based on the ``compression`` argument passed into the aggregates the accuracy can be increased with the tradeoff of more data being included in the summary that is shared between the workers and the coordinator. For a full explanation on how to use the aggregates in the tdigest extension have a look at the documentation on the official tdigest github repository.

.. _limit_pushdown:

Limit Pushdown
---------------------

Citus also pushes down the limit clauses to the shards on the workers wherever possible to minimize the amount of data transferred across network.

However, in some cases, SELECT queries with LIMIT clauses may need to fetch all rows from each shard to generate exact results. For example, if the query requires ordering by the aggregate column, it would need results of that column from all shards to determine the final aggregate value. This reduces performance of the LIMIT clause due to high volume of network data transfer. In such cases, and where an approximation would produce meaningful results, Citus provides an option for network efficient approximate LIMIT clauses.

LIMIT approximations are disabled by default and can be enabled by setting the configuration parameter citus.limit_clause_row_fetch_count. On the basis of this configuration value, Citus will limit the number of rows returned by each task for aggregation on the coordinator. Due to this limit, the final results may be approximate. Increasing this limit will increase the accuracy of the final results, while still providing an upper bound on the number of rows pulled from the workers.

.. code-block:: postgresql

    SET citus.limit_clause_row_fetch_count to 10000;

Views on Distributed Tables
---------------------------

Citus supports all views on distributed tables. For an overview of views' syntax and features, see the PostgreSQL documentation for `CREATE VIEW <https://www.postgresql.org/docs/current/static/sql-createview.html>`_.

Note that some views cause a less efficient query plan than others. For more about detecting and improving poor view performance, see :ref:`subquery_perf`. (Views are treated internally as subqueries.)

Citus supports materialized views as well, and stores them as local tables on the coordinator node. Using them in distributed queries after materialization requires wrapping them in a subquery, a technique described in :ref:`join_local_dist`.

.. _joins:

Joins
-----

Citus supports equi-JOINs between any number of tables irrespective of their size and distribution method. The query planner chooses the optimal join method and join order based on how tables are distributed. It evaluates several possible join orders and creates a join plan which requires minimum data to be transferred across network.

Co-located joins
~~~~~~~~~~~~~~~~

When two tables are :ref:`co-located <colocation>` then they can be joined efficiently on their common distribution columns. A co-located join is the most efficient way to join two large distributed tables.

Internally, the Citus coordinator knows which shards of the co-located tables might match with shards of the other table by looking at the distribution column metadata. This allows Citus to prune away shard pairs which cannot produce matching join keys. The joins between remaining shard pairs are executed in parallel on the workers and then the results are returned to the coordinator.

.. note::

  Be sure that the tables are distributed into the same number of shards and that the distribution columns of each table have exactly matching types. Attempting to join on columns of slightly different types such as int and bigint can cause problems.

Reference table joins
~~~~~~~~~~~~~~~~~~~~~

:ref:`reference_tables` can be used as "dimension" tables to join efficiently with large "fact" tables. Because reference tables are replicated in full across all worker nodes, a reference join can be decomposed into local joins on each worker and performed in parallel. A reference join is like a more flexible version of a co-located join because reference tables aren't distributed on any particular column and are free to join on any of their columns.

Reference tables can also join with tables local to the coordinator node, but only if you enable reference table placement on the coordinator. See :ref:`join_local_ref`.

.. _repartition_joins:

Repartition joins
~~~~~~~~~~~~~~~~~

In some cases, you may need to join two tables on columns other than the distribution column. For such cases, Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases the table(s) to be partitioned are determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, co-located joins are more efficient than repartition joins as repartition joins require shuffling of data. So, you should try to distribute your tables by the common join keys whenever possible.
