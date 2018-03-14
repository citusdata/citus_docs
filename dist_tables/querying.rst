.. _querying:

Querying Distributed Tables (SQL)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

As discussed in the previous sections, Citus is an extension which extends the latest PostgreSQL for distributed execution. This means that you can use standard PostgreSQL `SELECT <http://www.postgresql.org/docs/current/static/sql-select.html>`_ queries on the Citus coordinator for querying. Citus will then parallelize the SELECT queries involving complex selections, groupings and orderings, and JOINs to speed up the query performance. At a high level, Citus partitions the SELECT query into smaller query fragments, assigns these query fragments to workers, oversees their execution, merges their results (and orders them if needed), and returns the final result to the user.

In the following sections, we discuss the different types of queries you can run using Citus.

.. _aggregate_functions:

Aggregate Functions
###################

Citus supports and parallelizes most aggregate functions supported by PostgreSQL. Citus's query planner transforms the aggregate into its commutative and associative form so it can be parallelized. In this process, the workers run an aggregation query on the shards and the coordinator then combines the results from the workers to produce the final output.

.. _count_distinct:

Count (Distinct) Aggregates
---------------------------

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

1. Create the hll extension on all the PostgreSQL instances

   ::

       CREATE EXTENSION hll;

3. Enable count distinct approximations by setting the Citus.count_distinct_error_rate configuration value. Lower values for this configuration setting are expected to give more accurate results but take more time for computation. We recommend setting this to 0.005.

   ::

       SET citus.count_distinct_error_rate to 0.005;

   After this step, count(distinct) aggregates automatically switch to using HLL, with no changes necessary to your queries. You should be able to run approximate count distinct queries on any column of the table.

HyperLogLog Column
-------------------

Certain users already store their data as HLL columns. In such cases, they can dynamically roll up those data by creating custom aggregates within Citus.

As an example, if you want to run the hll_union aggregate function on your data stored as hll, you can define an aggregate function like below :

::

    CREATE AGGREGATE sum (hll)
    (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
    );


You can then call sum(hll_column) to roll up those columns within the database. Please note that these custom aggregates need to be created both on the coordinator and the workers.

.. _limit_pushdown:

Limit Pushdown
#####################

Citus pushes limit clauses down to the shards on workers wherever possible to minimize the amount of data transferred across the network. For example, if a select query with limit clause groups by a table's distribution column, then Citus will push the query down and run it directly on each worker. For instance, in a distributed table of deliveries partitioned geographically, we can take a sample of the number of drivers delivering in a few areas:

.. code-block:: sql

  EXPLAIN
  SELECT location_id, count(driver_id)
  FROM deliveries
  GROUP BY location_id
  LIMIT 5;

::

  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                           QUERY PLAN                                                             │
  ├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Limit  (cost=0.00..0.00 rows=0 width=0)                                                                                          │
  │   ->  HashAggregate  (cost=0.00..0.00 rows=0 width=0)                                                                            │
  │     Group Key: remote_scan.worker_column_2                                                                                       │
  │     ->  Custom Scan (Citus Real-Time)  (cost=0.00..0.00 rows=0 width=0)                                                          │
  │       Task Count: 32                                                                                                             │
  │       Tasks Shown: One of 32                                                                                                     │
  │       ->  Task                                                                                                                   │
  │         Node: host=localhost port=5433 dbname=postgres                                                                           │
  │         ->  Limit  (cost=0.15..0.64 rows=5 width=16)                                                                             │
  │           ->  GroupAggregate  (cost=0.15..69.15 rows=700 width=16)                                                               │
  │             Group Key: location_id                                                                                               │
  │             ->  Index Only Scan using deliveries_pkey_102360 on deliveries_102360 companies  (cost=0.15..58.65 rows=700 width=8) │
  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
  (12 rows)

Notice how the limit occurs twice in the plan: once at the final step in the coordinator, and also down in the query run on the workers. This limits how much data each worker returns to the coordinator.

However, in some cases SELECT queries with LIMIT clauses may need to fetch all rows from each shard to generate exact results. For example, if we had added an ORDER BY the driver count then the coordinator would need results from all shards to determine the final aggregate value. No individual worker knows which rows are safe to omit, and would send back all rows. This reduces performance of the LIMIT clause due to high volume of network data transfer.

In such cases, and where an approximation would produce meaningful results, Citus provides an option for network-efficient approximate LIMIT clauses.

::

    SET citus.limit_clause_row_fetch_count to 10000;

LIMIT approximations are disabled by default and can be enabled by setting the configuration parameter citus.limit_clause_row_fetch_count. On the basis of this configuration value, Citus will limit the number of rows returned by each task for aggregation on the coordinator. Due to this limit, the final results may be approximate. Increasing this limit will increase the accuracy of the final results, while still providing an upper bound on the number of rows pulled from the workers.

.. _joins:

Joins
#####

Citus supports equi-JOINs between any number of tables irrespective of their size and distribution method. The query planner chooses the optimal join method and join order based on how tables are distributed. It evaluates several possible join orders and creates a join plan which requires minimum data to be transferred across network.

Co-located joins
----------------

When two tables are :ref:`co-located <colocation>` then they can be joined efficiently on their common distribution columns. A co-located join is the most efficient way to join two large distributed tables.

Internally, the Citus coordinator knows which shards of the co-located tables might match with shards of the other table by looking at the distribution column metadata. This allows Citus to prune away shard pairs which cannot produce matching join keys. The joins between remaining shard pairs are executed in parallel on the workers and then the results are returned to the coordinator.

.. note::

  Be sure that the tables are distributed into the same number of shards and that the distribution columns of each table have exactly matching types. Attempting to join on columns of slightly different types such as int and bigint can cause problems.

Reference table joins
---------------------

:ref:`reference_tables` can be used as "dimension" tables to join efficiently with large "fact" tables. Because reference tables are replicated in full across all worker nodes, a reference join can be decomposed into local joins on each worker and performed in parallel. A reference join is like a more flexible version of a co-located join because reference tables aren't distributed on any particular column and are free to join on any of their columns.

.. _repartition_joins:

Repartition joins
-----------------

In some cases, you may need to join two tables on columns other than the distribution column. For such cases, Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases the table(s) to be partitioned are determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, co-located joins are more efficient than repartition joins as repartition joins require shuffling of data. So, you should try to distribute your tables by the common join keys whenever possible.

Views on Distributed Tables
###########################

Citus supports all views on distributed tables. For an overview of views' syntax and features, see the PostgreSQL documentation for `CREATE VIEW <https://www.postgresql.org/docs/current/static/sql-createview.html>`_.

Note that some views cause a less efficient query plan than others. For more about detecting and improving poor view performance, see :ref:`subquery_perf`. (Views are treated internally as subqueries.)

Citus supports materialized views as well, and stores them as local tables on the coordinator node. Using them in distributed queries after materialization requires wrapping them in a subquery, a technique described in :ref:`join_local_dist`.

.. _query_performance:

Query Performance
#################

Citus parallelizes incoming queries by breaking it into multiple fragment queries ("tasks") which run on the worker shards in parallel. This allows Citus to utilize the processing power of all the nodes in the cluster and also of individual cores on each node for each query. Due to this parallelization, you can get performance which is cumulative of the computing power of all of the cores in the cluster leading to a dramatic decrease in query times versus PostgreSQL on a single server.

Citus employs a two stage optimizer when planning SQL queries. The first phase involves converting the SQL queries into their commutative and associative form so that they can be pushed down and run on the workers in parallel. As discussed in previous sections, choosing the right distribution column and distribution method allows the distributed query planner to apply several optimizations to the queries. This can have a significant impact on query performance due to reduced network I/O.

Citus’s distributed executor then takes these individual query fragments and sends them to worker PostgreSQL instances. There are several aspects of both the distributed planner and the executor which can be tuned in order to improve performance. When these individual query fragments are sent to the workers, the second phase of query optimization kicks in. The workers are simply running extended PostgreSQL servers and they apply PostgreSQL's standard planning and execution logic to run these fragment SQL queries. Therefore, any optimization that helps PostgreSQL also helps Citus. PostgreSQL by default comes with conservative resource settings; and therefore optimizing these configuration settings can improve query times significantly.

We discuss the relevant performance tuning steps in the :ref:`performance_tuning` section of the documentation.
