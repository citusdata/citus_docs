.. _working_with_distributed_tables:

Concepts
########

Citus provides distributed functionality by extending PostgreSQL using the hook and extension APIs. This allows users to benefit from the features that come with the rich PostgreSQL ecosystem. These features include, but aren’t limited to, support for a wide range of `data types <http://www.postgresql.org/docs/9.5/static/datatype.html>`_ (including semi-structured data types like jsonb and hstore), `operators and functions <http://www.postgresql.org/docs/9.5/static/functions.html>`_, full text search, and other extensions such as `PostGIS <http://postgis.net/>`_ and `HyperLogLog <https://github.com/aggregateknowledge/postgresql-hll>`_. Further, proper use of the extension APIs enable compatibility with standard PostgreSQL tools such as `pgAdmin <http://www.pgadmin.org/>`_, `pg_backup <http://www.postgresql.org/docs/9.5/static/backup.html>`_, and `pg_upgrade <http://www.postgresql.org/docs/9.5/static/pgupgrade.html>`_.

Citus users can leverage standard PostgreSQL interfaces with minimal modifications to enable distributed behavior. This includes commands for creating tables, loading data, updating rows, and also for querying. You can find a full reference of the PostgreSQL constructs `here <http://www.postgresql.org/docs/9.5/static/sql-commands.html>`_. We also discuss the relevant commands in our documentation as needed. Before we dive into the syntax for these commands, we briefly discuss an important concept which must be decided during distributed table creation: the "distribution column" whose values determine the destination shard for each row.

.. _distribution_column_method:

Distribution Column
-------------------

Every distributed table in Citus has exactly one column which is chosen as the distribution column. This informs the database to maintain statistics about the distribution column in each shard. Citus’s distributed query optimizer then leverages these statistics to determine how best a query should be executed.

Typically, you should choose that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then Citus executes the join only between those shards which have matching / overlapping distribution column ranges. This helps in greatly reducing both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps Citus push down several operations directly to the worker shards, hence reducing network I/O.

.. note::
  Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

The best choice of distribution column varies depending on the use case and queries. Two common scenarios are the multi-tenant B2B application and the realtime analytics dashboard. In the former all tables include a tenant id and are distributed by it. When SQL queries are restricted to accessing data about a single tenant then Citus can execute them within a single shard. Having all data colocated in a shard is efficient and supports all SQL features. However running queries on a single shard limits the ability to parallelize execution.

The other common option, realtime analytics, distributes by another column (such as user id). The queries in this scenario typically request aggregates information from multiple shards. This permits query parallelism but restricts some of the SQL features available, due to the constraints of being a distributed system.
