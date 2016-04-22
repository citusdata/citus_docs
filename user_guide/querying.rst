.. _querying:

Querying
########

As discussed in the previous sections, CitusDB merely extends the the latest PostgreSQL version. This means that users can use standard PostgreSQL `SELECT <http://www.postgresql.org/docs/9.4/static/sql-select.html>`_ commands on the master node for querying. CitusDB then parallelizes the SELECT queries involving look-ups, complex selections, groupings and orderings, and JOINs to speed up the query performance. At a high level, CitusDB partitions the SELECT query into smaller query fragments, assigns these query fragments to worker nodes, oversees their execution, merges their results (and orders them if needed), and returns the final result to the user.

In the following sections, we discuss the different types of queries users can run using CitusDB.

.. toctree::
   :hidden:
   
   aggregate_functions.rst
   limit_pushdown.rst
   joins.rst
   data_warehousing_queries.rst
   query_performance.rst



