.. _querying:

Querying Distributed Tables (SQL)
=================================

As discussed in the previous sections, Citus is an extension which extends the latest PostgreSQL for distributed execution. This means that you can use standard PostgreSQL `SELECT <http://www.postgresql.org/docs/current/static/sql-select.html>`_ queries on the Citus coordinator for querying. Citus will then parallelize the SELECT queries involving complex selections, groupings and orderings, and JOINs to speed up the query performance. At a high level, Citus partitions the SELECT query into smaller query fragments, assigns these query fragments to workers, oversees their execution, merges their results (and orders them if needed), and returns the final result to the user.

In the following sections, we discuss the different types of queries you can run using Citus.

.. _aggregate_functions:

Aggregate Functions
-------------------

Citus supports and parallelizes most aggregate functions supported by PostgreSQL. Citus's query planner transforms the aggregate into its commutative and associative form so it can be parallelized. In this process, the workers run an aggregation query on the shards and the coordinator then combines the results from the workers to produce the final output.

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

2. Create the hll extension on all the PostgreSQL instances

  .. code-block:: postgresql

    CREATE EXTENSION hll;

3. Enable count distinct approximations by setting the Citus.count_distinct_error_rate configuration value. Lower values for this configuration setting are expected to give more accurate results but take more time for computation. We recommend setting this to 0.005.

  .. code-block:: postgresql

    SET citus.count_distinct_error_rate to 0.005;

  After this step, count(distinct) aggregates automatically switch to using HLL, with no changes necessary to your queries. You should be able to run approximate count distinct queries on any column of the table.

HyperLogLog Column
$$$$$$$$$$$$$$$$$$

Certain users already store their data as HLL columns. In such cases, they can dynamically roll up those data by creating custom aggregates within Citus.

As an example, if you want to run the hll_union aggregate function on your data stored as hll, you can define an aggregate function like below :

.. code-block:: postgresql

  CREATE AGGREGATE sum (hll)
  (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
  );

You can then call sum(hll_column) to roll up those columns within the database. Please note that these custom aggregates need to be created both on the coordinator and the workers.

.. _topn:

Estimating Top N Items
~~~~~~~~~~~~~~~~~~~~~~

Similar to how HLL efficiently estimates the number of distinct items in a set, the `TopN PostgreSQL extension <https://github.com/citusdata/postgresql-topn>`_ simultaneously counts many items. It, too, stores an approximation in a bounded amount of space. It is also pre-installed on Citus Cloud.

Fundamentally the extension tracks a multi-set as a JSON object.

.. code-block:: postgres

  -- starting from nothing, record that we saw an "a"
  select topn_add('{}', 'a');
  -- => {"a": 1}

  -- record the sighting of another "a"
  select topn_add(topn_add('{}', 'a'), 'a');
  -- => {"a": 2}

It also provides aggregations to scan multiple values.

.. code-block:: postgres

  -- count values from a normal distribution
  SELECT topn_add_agg(floor(abs(i))::text)
    FROM normal_rand(1000, 5, 0.7) i;
  -- => {"2": 1, "3": 74, "4": 420, "5": 425, "6": 77, "7": 3}

If the number of distinct values crosses a threshold, the aggregation drops information for those seen least frequently. This keeps space usage under control. The threshold can be controlled by the ``topn.number_of_counters`` GUC. Its default value is 1000.

Notice the casting in ``floor(abs(i))::text``. TopN works with text values only, so other values such as integers must be converted first.

Now onto realistic applications. The TopN extension shines when materializing aggregates. For instance, let's ingest Amazon product reviews from the year 2000 and use TopN to query it quickly. First download the dataset:

.. code-block:: bash

  curl -L https://examples.citusdata.com/customer_reviews_2000.csv.gz | \
    gunzip > reviews.csv

Next, ingest it into the database:

.. code-block:: postgresql

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

  \COPY customer_reviews FROM 'reviews.csv' WITH CSV;

Next we'll add the extension, create a destination table to store the json data generated by TopN, and apply the ``topn_add_agg`` function we saw previously.

.. code-block:: postgresql

  -- note: Citus Cloud has extension already
  CREATE EXTENSION topn;

  -- a table to materialize the daily aggregate
  CREATE TABLE reviews_by_day
  (
    review_date date UNIQUE,
    agg_data jsonb
  );

  -- materialize how many reviews each product got per day
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
  │ 2000-01-03  │ 0345417623 │        12 │
  │ 2000-01-04  │ 0375404368 │        14 │
  │ 2000-01-05  │ B00000JJCZ │        17 │
  └─────────────┴────────────┴───────────┘


The json fields created by TopN can be merged with ``topn_union`` and ``topn_union_agg``. We can use the latter to merge the data for the entire first month and list the five products most reviewed during that period.

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

For more details and examples see the TopN readme.

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

.. _repartition_joins:

Repartition joins
~~~~~~~~~~~~~~~~~

In some cases, you may need to join two tables on columns other than the distribution column. For such cases, Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases the table(s) to be partitioned are determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, co-located joins are more efficient than repartition joins as repartition joins require shuffling of data. So, you should try to distribute your tables by the common join keys whenever possible.
