.. _citus_query_processing:

Query Processing
================

A Citus cluster consists of a coordinator instance and multiple worker instances. The data is sharded on the workers while the coordinator stores metadata about these shards. All queries issued to the cluster are executed via the coordinator. The coordinator partitions the query into smaller query fragments where each query fragment can be run independently on a shard. The coordinator then assigns the query fragments to workers, oversees their execution, merges their results, and returns the final result to the user. The query processing architecture can be described in brief by the diagram below.

.. image:: ../images/citus-high-level-arch.png
    :alt: diagram of queries being distributed through coordinator node to workers

Citus’s query processing pipeline involves the two components:

* **Distributed Query Planner and Executor**
* **PostgreSQL Planner and Executor**

We discuss them in greater detail in the subsequent sections.

.. _distributed_query_planner:

Distributed Query Planner
-------------------------

Citus’s distributed query planner takes in a SQL query and plans it for distributed execution.

For SELECT queries, the planner first creates a plan tree of the input query and transforms it into its commutative and associative form so it can be parallelized. It also applies several optimizations to ensure that the queries are executed in a scalable manner, and that network I/O is minimized.

Next, the planner breaks the query into two parts - the coordinator query which runs on the coordinator and the worker query fragments which run on individual shards on the workers. The planner then assigns these query fragments to the workers such that all their resources are used efficiently. After this step, the distributed query plan is passed on to the distributed executor for execution.

The planning process for key-value lookups on the distribution column or modification queries is slightly different as they hit exactly one shard. Once the planner receives an incoming query, it needs to decide the correct shard to which the query should be routed. To do this, it extracts the distribution column in the incoming row and looks up the metadata to determine the right shard for the query. Then, the planner rewrites the SQL of that command to reference the shard table instead of the original table. This re-written plan is then passed to the distributed executor.

.. _distributed_query_executor:

Distributed Query Executor
--------------------------

Citus’s distributed executor runs distributed query plans and handles failures. The executor is well suited for getting fast responses to queries involving filters, aggregations and co-located joins, as well as running single-tenant queries with full SQL coverage. It opens one connection per shard to the workers as needed and sends all fragment queries to them. It then fetches the results from each fragment query, merges them, and gives the final results back to the user.

.. _push_pull_execution:

Subquery/CTE Push-Pull Execution
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If necessary Citus can gather results from subqueries and CTEs into the coordinator node and then push them back across workers for use by an outer query. This allows Citus to support a greater variety of SQL constructs.

For example, having subqueries in a WHERE clause sometimes cannot execute inline at the same time as the main query, but must be done separately. Suppose a web analytics application maintains a ``page_views`` table partitioned by ``page_id``. To query the number of visitor hosts on the top twenty most visited pages, we can use a subquery to find the list of pages, then an outer query to count the hosts.

.. code-block:: sql

  SELECT page_id, count(distinct host_ip)
  FROM page_views
  WHERE page_id IN (
    SELECT page_id
    FROM page_views
    GROUP BY page_id
    ORDER BY count(*) DESC
    LIMIT 20
  )
  GROUP BY page_id;

The executor would like to run a fragment of this query against each shard by page_id, counting distinct host_ips, and combining the results on the coordinator. However, the LIMIT in the subquery means the subquery cannot be executed as part of the fragment. By recursively planning the query Citus can run the subquery separately, push the results to all workers, run the main fragment query, and pull the results back to the coordinator. The "push-pull" design supports subqueries like the one above.

Let's see this in action by reviewing the `EXPLAIN <https://www.postgresql.org/docs/current/static/sql-explain.html>`_ output for this query. It's fairly involved:

::

  GroupAggregate  (cost=0.00..0.00 rows=0 width=0)
    Group Key: remote_scan.page_id
    ->  Sort  (cost=0.00..0.00 rows=0 width=0)
      Sort Key: remote_scan.page_id
      ->  Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=0 width=0)
        ->  Distributed Subplan 6_1
          ->  Limit  (cost=0.00..0.00 rows=0 width=0)
            ->  Sort  (cost=0.00..0.00 rows=0 width=0)
              Sort Key: COALESCE((pg_catalog.sum((COALESCE((pg_catalog.sum(remote_scan.worker_column_2))::bigint, '0'::bigint))))::bigint, '0'::bigint) DESC
              ->  HashAggregate  (cost=0.00..0.00 rows=0 width=0)
                Group Key: remote_scan.page_id
                ->  Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=0 width=0)
                  Task Count: 32
                  Tasks Shown: One of 32
                  ->  Task
                    Node: host=localhost port=9701 dbname=postgres
                    ->  HashAggregate  (cost=54.70..56.70 rows=200 width=12)
                      Group Key: page_id
                      ->  Seq Scan on page_views_102008 page_views  (cost=0.00..43.47 rows=2247 width=4)
        Task Count: 32
        Tasks Shown: One of 32
        ->  Task
          Node: host=localhost port=9701 dbname=postgres
          ->  HashAggregate  (cost=84.50..86.75 rows=225 width=36)
            Group Key: page_views.page_id, page_views.host_ip
            ->  Hash Join  (cost=17.00..78.88 rows=1124 width=36)
              Hash Cond: (page_views.page_id = intermediate_result.page_id)
              ->  Seq Scan on page_views_102008 page_views  (cost=0.00..43.47 rows=2247 width=36)
              ->  Hash  (cost=14.50..14.50 rows=200 width=4)
                ->  HashAggregate  (cost=12.50..14.50 rows=200 width=4)
                  Group Key: intermediate_result.page_id
                  ->  Function Scan on read_intermediate_result intermediate_result  (cost=0.00..10.00 rows=1000 width=4)

Let's break it apart and examine each piece.

::

  GroupAggregate  (cost=0.00..0.00 rows=0 width=0)
    Group Key: remote_scan.page_id
    ->  Sort  (cost=0.00..0.00 rows=0 width=0)
      Sort Key: remote_scan.page_id

The root of the tree is what the coordinator node does with the results from the workers. In this case it is grouping them, and GroupAggregate requires they be sorted first.

::

      ->  Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=0 width=0)
        ->  Distributed Subplan 6_1
  .

The custom scan has two large sub-trees, starting with a "distributed subplan."

::

          ->  Limit  (cost=0.00..0.00 rows=0 width=0)
            ->  Sort  (cost=0.00..0.00 rows=0 width=0)
              Sort Key: COALESCE((pg_catalog.sum((COALESCE((pg_catalog.sum(remote_scan.worker_column_2))::bigint, '0'::bigint))))::bigint, '0'::bigint) DESC
              ->  HashAggregate  (cost=0.00..0.00 rows=0 width=0)
                Group Key: remote_scan.page_id
                ->  Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=0 width=0)
                  Task Count: 32
                  Tasks Shown: One of 32
                  ->  Task
                    Node: host=localhost port=9701 dbname=postgres
                    ->  HashAggregate  (cost=54.70..56.70 rows=200 width=12)
                      Group Key: page_id
                      ->  Seq Scan on page_views_102008 page_views  (cost=0.00..43.47 rows=2247 width=4)
  .

Worker nodes run the above for each of the thirty-two shards (Citus is choosing one representative for display). We can recognize all the pieces of the ``IN (…)`` subquery: the sorting, grouping and limiting. When all workers have completed this query, they send their output back to the coordinator which puts it together as "intermediate results."

::

        Task Count: 32
        Tasks Shown: One of 32
        ->  Task
          Node: host=localhost port=9701 dbname=postgres
          ->  HashAggregate  (cost=84.50..86.75 rows=225 width=36)
            Group Key: page_views.page_id, page_views.host_ip
            ->  Hash Join  (cost=17.00..78.88 rows=1124 width=36)
              Hash Cond: (page_views.page_id = intermediate_result.page_id)
  .

Citus starts another executor job in this second subtree. It's going to count distinct hosts in page_views. It uses a JOIN to connect with the intermediate results. The intermediate results will help it restrict to the top twenty pages.

::

              ->  Seq Scan on page_views_102008 page_views  (cost=0.00..43.47 rows=2247 width=36)
              ->  Hash  (cost=14.50..14.50 rows=200 width=4)
                ->  HashAggregate  (cost=12.50..14.50 rows=200 width=4)
                  Group Key: intermediate_result.page_id
                  ->  Function Scan on read_intermediate_result intermediate_result  (cost=0.00..10.00 rows=1000 width=4)
  .

The worker internally retrieves intermediate results using a ``read_intermediate_result`` function which loads data from a file that was copied in from the coordinator node.

This example showed how Citus executed the query in multiple steps with a distributed subplan, and how you can use EXPLAIN to learn about distributed query execution.

.. _postgresql_planner_executor:

PostgreSQL planner and executor
--------------------------------

Once the distributed executor sends the query fragments to the workers, they are processed like regular PostgreSQL queries. The PostgreSQL planner on that worker chooses the most optimal plan for executing that query locally on the corresponding shard table. The PostgreSQL executor then runs that query and returns the query results back to the distributed executor. You can learn more about the PostgreSQL `planner <http://www.postgresql.org/docs/current/static/planner-optimizer.html>`_ and `executor <http://www.postgresql.org/docs/current/static/executor.html>`_ from the PostgreSQL manual. Finally, the distributed executor passes the results to the coordinator for final aggregation.
