.. _working_with_distributed_tables:

Working with distributed tables
################################

Citus provides distributed functionality by extending PostgreSQL using the hook and extension APIs. This allows users to benefit from the features that come with the rich PostgreSQL ecosystem. These features include, but aren’t limited to, support for a wide range of `data types <http://www.postgresql.org/docs/9.5/static/datatype.html>`_ (including semi-structured data types like jsonb and hstore), `operators and functions <http://www.postgresql.org/docs/9.5/static/functions.html>`_, full text search, and other extensions such as `PostGIS <http://postgis.net/>`_ and `HyperLogLog <https://github.com/aggregateknowledge/postgresql-hll>`_. Further, proper use of the extension APIs enable compatibility with standard PostgreSQL tools such as `pgAdmin <http://www.pgadmin.org/>`_, `pg_backup <http://www.postgresql.org/docs/9.5/static/backup.html>`_, and `pg_upgrade <http://www.postgresql.org/docs/9.5/static/pgupgrade.html>`_.

Citus users can leverage standard PostgreSQL interfaces with minimal modifications to enable distributed behavior. This includes commands for creating tables, loading data, updating rows, and also for querying. You can find a full reference of the PostgreSQL constructs `here <http://www.postgresql.org/docs/9.5/static/sql-commands.html>`_. We also discuss the relevant commands in our documentation as needed. Before we dive into the syntax for these commands, we briefly discuss two important concepts which must be decided during distributed table creation: the distribution column and distribution method.

.. _distribution_column_method: 

Distribution Column
-------------------

Every distributed table in Citus has exactly one column which is chosen as the distribution column. This informs the database to maintain statistics about the distribution column in each shard. Citus’s distributed query optimizer then leverages these statistics to determine how best a query should be executed.

Typically, you should choose that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then Citus executes the join only between those shards which have matching / overlapping distribution column ranges. This helps in greatly reducing both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps Citus push down several operations directly to the worker shards, hence reducing network I/O.

.. note::
  Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

The best option for the distribution column varies depending on the use case and the queries. In general, we find two common patterns: (1) **distributing by time** (timestamp, review date, order date), and (2) **distributing by identifier** (user id, order id, application id). Typically, data arrives in a time-ordered series. So, if your use case works well with batch loading, it is easiest to distribute your largest tables by time, and load it into Citus in intervals of N minutes. In some cases, it might be worth distributing your incoming data by another key (e.g. user id, application id) and Citus will route your rows to the correct shards when they arrive. This can be beneficial when most of your queries involve a filter or joins on user id or order id.

Distribution Method
-------------------

The next step after choosing the right distribution column is deciding the right distribution method. Citus supports two distribution methods: append and hash. Citus also provides the option for range distribution but that currently requires manual effort to set up.

As the name suggests, append based distribution is more suited to append-only use cases. This typically includes event based data which arrives in a time-ordered series. You can then distribute your largest tables by time, and batch load your events into Citus in intervals of N minutes. This data model can be generalized to a number of time series use cases; for example, each line in a website's log file, machine activity logs or aggregated website events. Append based distribution supports more efficient range queries. This is because given a range query on the distribution key, the Citus query planner can easily determine which shards overlap that range and send the query to only to relevant shards.

Hash based distribution is more suited to cases where you want to do real-time inserts along with analytics on your data or want to distribute by a non-ordered column (eg. user id). This data model is relevant for real-time analytics use cases; for example, actions in a mobile application, user website events, or social media analytics. In this case, Citus will maintain minimum and maximum hash ranges for all the created shards. Whenever a row is inserted, updated or deleted, Citus will redirect the query to the correct shard and issue it locally. This data model is more suited for doing co-located joins and for queries involving equality based filters on the distribution column.

Citus uses slightly different syntaxes for creation and manipulation of append and hash distributed tables. Also, the operations supported on the tables differ based on the distribution method chosen. In the sections that follow, we describe the syntax for creating append and hash distributed tables, and also describe the operations which can be done on them. We also briefly discuss how you can setup range distribution manually.
