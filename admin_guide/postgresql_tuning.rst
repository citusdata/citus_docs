.. _postgresql_tuning:

PostgreSQL tuning
#################

CitusDB partitions an incoming query into fragment queries, and sends them to the worker nodes for parallel processing. The worker nodes then apply PostgreSQL's standard planning and execution logic for these queries. So, the first step in tuning CitusDB is tuning the PostgreSQL configuration parameters on the worker nodes for high performance.

This step involves loading a small portion of the data into regular PostgreSQL tables on the worker nodes. These tables would be representative of shards on which your queries would run once the full data has been distributed. Then, you can run the fragment queries on the individual shards and use standard PostgreSQL tuning to optimize query performance.

The first set of such optimizations relates to configuration settings for the database. PostgreSQL by default comes with conservative resource settings; and among these settings, shared_buffers and work_mem are probably the most important ones in optimizing read performance. We discuss these parameters in brief below. Apart from them, several other configuration settings impact query performance. These settings are covered in more detail in the `PostgreSQL manual <http://www.postgresql.org/docs/9.4/static/runtime-config.html>`_ and are also discussed in the `PostgreSQL 9.0 High Performance book <http://www.amazon.com/PostgreSQL-High-Performance-Gregory-Smith/dp/184951030X>`_.

shared_buffers defines the amount of memory allocated to the database for caching data, and defaults to 128MB. If you have a worker node with 1GB or more RAM, a reasonable starting value for shared_buffers is 1/4 of the memory in your system. There are some workloads where even larger settings for shared_buffers are effective, but given the way PostgreSQL also relies on the operating system cache, it's unlikely you'll find using more than 25% of RAM to work better than a smaller amount.

If you do a lot of complex sorts, then increasing work_mem allows PostgreSQL to do larger in-memory sorts which will be faster than disk-based equivalents. If you see lot of disk activity on your worker node inspite of having a decent amount of memory, then increasing work_mem to a higher value can be useful. This will help PostgreSQL in choosing more efficient query plans and allow for greater amount of operations to occur in memory.

Other than the above configuration settings, the PostgreSQL query planner relies on statistical information about the contents of tables to generate good plans. These statistics are gathered when ANALYZE is run, which is enabled by default. You can learn more about the PostgreSQL planner and the ANALYZE command in greater detail in the `PostgreSQL documentation <http://www.postgresql.org/docs/9.4/static/sql-analyze.html>`_.

Lastly, you can create indexes on your tables to enhance database performance. Indexes allow the database to find and retrieve specific rows much faster than it could do without an index. To choose which indexes give the best performance, you can run the query with `EXPLAIN <http://www.postgresql.org/docs/9.4/static/sql-explain.html>`_ to view query plans and optimize the slower parts of the query. After an index is created, the system has to keep it synchronized with the table which adds overhead to data manipulation operations. Therefore, indexes that are seldom or never used in queries should be removed.

For write performance, you can use general PostgreSQL configuration tuning to increase INSERT rates. We commonly recommend increasing checkpoint_segments and checkpoint_timeout settings. Also, depending on the reliability requirements of your application, you can choose to change fsync or synchronous_commit values.
