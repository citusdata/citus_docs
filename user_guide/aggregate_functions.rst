.. _aggregate_functions:

Aggregate Functions
###################


CitusDB supports and parallelizes most aggregate functions supported by PostgreSQL. The query planner transforms the aggregate into its commutative and associative form so it can be parallelized. In this process, the worker nodes run an aggregation query on the shards and the master node then combines the results from the workers to produce the final output.

.. _count_distinct:

Count (Distinct) Aggregates
----------------------------------------

CitusDB supports count(distinct) aggregates in several ways. If the count(distinct) aggregate is on the distribution column, CitusDB can directly push down the query to the worker nodes. If not, CitusDB needs to repartition the underlying data in the cluster to parallelize count(distinct) aggregates and avoid pulling all rows to the master node.

To address the common use case of count(distinct) approximations, CitusDB provides an option of using the HyperLogLog algorithm to efficiently calculate approximate values for the count distincts on non-distribution key columns.

To enable count distinct approximations, you can follow the steps below:

(1) Create the hll extension on all the nodes (the master node and all the worker nodes). The extension already comes installed with the citusdb contrib package.

::

    CREATE EXTENSION hll;

(2) Enable count distinct approximations by setting the count_distinct_error_rate configuration value. Lower values for this configuration setting are expected to give more accurate results but take more time for computation. We recommend setting this to 0.005.

::

    SET count_distinct_error_rate to 0.005;

After this step, you should be able to run approximate count distinct queries on any column of the table.

HyperLogLog Column
----------------------------------------

Certain users already store their data as HLL columns. In such cases, they can dynamically roll up those data by creating custom aggregates within CitusDB.

As an example, if you want to run the hll_union aggregate function on your data stored as hll, you can define an aggregate function like below :

::

    CREATE AGGREGATE sum (hll)
    (
    sfunc = hll_union_trans,
    stype = internal,
    finalfunc = hll_pack
    );


The users can call sum(hll_column) to roll up those columns within CitusDB. Please note that these custom aggregates need to be created both on the master node and the worker node.
