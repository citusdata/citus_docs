.. _postgresql_planner_executor:

PostgreSQL planner and executor
################################


Once the distributed executor sends the query fragments to the worker nodes, they are processed like regular PostgreSQL queries.
The PostgreSQL planner on that worker node chooses the most optimal plan for executing that query locally on the corresponding shard table.
The PostgreSQL executor then runs that query and returns the query results back to the distributed executor. You can learn more about the PostgreSQL `planner <http://www.postgresql.org/docs/9.4/static/planner-optimizer.html>`_ and `executor <http://www.postgresql.org/docs/9.4/static/executor.html>`_ from the PostgreSQL manual. Finally, the distributed executor passes the results to the master node for final aggregation.
