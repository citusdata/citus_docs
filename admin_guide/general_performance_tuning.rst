.. _general_performance_tuning:

General
########

For higher INSERT performance, the factor which impacts insert rates the most is the level of concurrency. You should try to run several concurrent INSERT statements in parallel. This way you can achieve very high insert rates if you have a powerful master node and are able to use all the CPU cores on that node together.

An important performance tuning parameter in context of SELECT query performance is remote_task_check_interval. The master node assigns tasks to workers nodes, and then regularly checks with them about each task's progress. This configuration value sets the time interval between two consequent checks. Setting this parameter to a lower value reduces query times significantly for sub-second queries. For relatively long running queries (which take minutes as opposed to seconds), reducing this parameter might not be ideal as this would make the master node contact the workers more, incurring a higher overhead.

CitusDB has 2 different executor types for running SELECT queries. The desired executor can be selected by setting the task_executor_type configuration parameter. For shorter, high performance queries, users should try to use the real-time executor as much as possible. This is because the real time executor has a simpler architecture and a lower operational overhead. The task tracker executor is well suited for long running, complex queries which require dynamically repartitioning and shuffling data across worker nodes.

Other than the above, there are two configuration parameters which can be useful in cases where approximations produce meaningful results. These two parameters are the limit_clause_row_fetch_count and count_distinct_error_rate. The former sets the number of rows to fetch from each task while calculating limits while the latter sets the desired error rate when calculating approximate distinct counts. You can learn more about the applicability and usage of these parameters in the user guide sections: :ref:`count_distinct` and :ref:`limit_pushdown`.

