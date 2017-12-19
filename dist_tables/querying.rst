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

Citus also pushes down the limit clauses to the shards on the workers wherever possible to minimize the amount of data transferred across network.

However, in some cases, SELECT queries with LIMIT clauses may need to fetch all rows from each shard to generate exact results. For example, if the query requires ordering by the aggregate column, it would need results of that column from all shards to determine the final aggregate value. This reduces performance of the LIMIT clause due to high volume of network data transfer. In such cases, and where an approximation would produce meaningful results, Citus provides an option for network efficient approximate LIMIT clauses.

LIMIT approximations are disabled by default and can be enabled by setting the configuration parameter citus.limit_clause_row_fetch_count. On the basis of this configuration value, Citus will limit the number of rows returned by each task for aggregation on the coordinator. Due to this limit, the final results may be approximate. Increasing this limit will increase the accuracy of the final results, while still providing an upper bound on the number of rows pulled from the workers.

::

    SET citus.limit_clause_row_fetch_count to 10000;

.. _joins:

Joins
#####

Citus supports equi-JOINs between any number of tables irrespective of their size and distribution method. The query planner chooses the optimal join method and join order based on the statistics gathered from the distributed tables. It evaluates several possible join orders and creates a join plan which requires minimum data to be transferred across network.

To determine the best join strategy, Citus treats large and small tables differently while executing JOINs. The distributed tables are classified as large and small on the basis of the configuration entry citus.large_table_shard_count (default value: 4). The tables whose shard count exceeds this value are considered as large while the others small. In practice, the fact tables are generally the large tables while the dimension tables are the small tables.

Broadcast joins
----------------

This join type is used while joining small tables with each other or with a large table. This is a very common use case where you want to join the keys in the fact tables (large table) with their corresponding dimension tables (small tables). Citus replicates the small table to all workers where the large table's shards are present. Then, all the joins are performed locally on the workers in parallel. Subsequent join queries that involve the small table then use these cached shards.

Co-located joins
----------------------------

To join two large tables efficiently, it is advised that you distribute them on the same columns you used to join the tables. In this case, the Citus coordinator knows which shards of the tables might match with shards of the other table by looking at the distribution column metadata. This allows Citus to prune away shard pairs which cannot produce matching join keys. The joins between remaining shard pairs are executed in parallel on the workers and then the results are returned to the coordinator.

.. note::
  In order to benefit most from co-located joins, you should hash distribute your tables on the join key and use the same number of shards for both tables. If you do this, each shard will join with exactly one shard of the other table. Also, the shard creation logic will ensure that shards with the same distribution key ranges are on the same workers. This means no data needs to be transferred between the workers, leading to faster joins.

.. _repartition_joins:

Repartition joins
----------------------------

In some cases, you may need to join two tables on columns other than the distribution column. For such cases, Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query.

In such cases the table(s) to be partitioned are determined by the query optimizer on the basis of the distribution columns, join keys and sizes of the tables. With repartitioned tables, it can be ensured that only relevant shard pairs are joined with each other reducing the amount of data transferred across network drastically.

In general, co-located joins are more efficient than repartition joins as repartition joins require shuffling of data. So, you should try to distribute your tables by the common join keys whenever possible.

Views on Distributed Tables
###########################

Any view which filters a distributed table by equality on the distribution column has full support in Citus. For instance, consider a shortcut to list the orders for a certain tenant in a multi-tenant application:

.. code-block:: sql

  CREATE VIEW tenant_25_orders AS
  SELECT *
    FROM orders
   WHERE tenant_id = 25;

A view such as this, filtering ``tenant_id = 25``, can used with any other query involving tenant twenty-five. We can aggregate the view:

.. code-block:: sql

  SELECT count(*) FROM tenant_25_orders;

or join it with a table:

.. code-block:: sql

  SELECT e.*
    FROM tenant_25_orders t25o
    JOIN events e ON (
      t25o.tenant_id = e.tenant_id AND
      t25o.order_id = e.order_id
    );

Joining with other views is fine too, as long as we join by the distribution column. In this example even :code:`high_priority_events` is eligible for joining despite not itself filtering by the distribution column.

.. code-block:: sql

  CREATE VIEW high_priority_events AS
  SELECT *
    FROM events
   WHERE priority = 'HIGH';

  SELECT hpe.*
    FROM tenant_25_orders t25o
    JOIN high_priority_events hpe ON (
      t25o.tenant_id = hpe.tenant_id
    );

The :code:`tenant_25_orders` view is pretty rudimentary, but Citus supports views with more inside like aggregates and joins. This works as long as the view filters by the distribution column and includes that column in join conditions.

.. code-block:: sql

  CREATE VIEW t25_daily_web_order_count AS
  SELECT
    orders.tenant_id,
    order_date,
    count(*)
  FROM
    orders
    JOIN events ON (orders.tenant_id = events.tenant_id)
  WHERE
    orders.tenant_id = 25
    AND orders.order_type = 'WEB'
  GROUP BY
    orders.tenant_id,
    order_date
  ORDER BY count(*) DESC
  LIMIT 10;

For more details about how to make queries work well in the multi-tenant use case (including queries for use in views), see :ref:`mt_query_migration`.

Materialized Views
------------------

Citus supports materialized views that filter by tenant id, and stores them as local tables on the coordinator node. This means they cannot be used in distributed queries after materialization. To learn more about local vs distributed tables see :ref:`table_types`.

.. _query_performance:

Query Performance
#################

Citus parallelizes incoming queries by breaking it into multiple fragment queries ("tasks") which run on the worker shards in parallel. This allows Citus to utilize the processing power of all the nodes in the cluster and also of individual cores on each node for each query. Due to this parallelization, you can get performance which is cumulative of the computing power of all of the cores in the cluster leading to a dramatic decrease in query times versus PostgreSQL on a single server.

Citus employs a two stage optimizer when planning SQL queries. The first phase involves converting the SQL queries into their commutative and associative form so that they can be pushed down and run on the workers in parallel. As discussed in previous sections, choosing the right distribution column and distribution method allows the distributed query planner to apply several optimizations to the queries. This can have a significant impact on query performance due to reduced network I/O.

Citus’s distributed executor then takes these individual query fragments and sends them to worker PostgreSQL instances. There are several aspects of both the distributed planner and the executor which can be tuned in order to improve performance. When these individual query fragments are sent to the workers, the second phase of query optimization kicks in. The workers are simply running extended PostgreSQL servers and they apply PostgreSQL's standard planning and execution logic to run these fragment SQL queries. Therefore, any optimization that helps PostgreSQL also helps Citus. PostgreSQL by default comes with conservative resource settings; and therefore optimizing these configuration settings can improve query times significantly.

We discuss the relevant performance tuning steps in the :ref:`performance_tuning` section of the documentation.
