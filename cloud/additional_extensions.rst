.. include:: deprecated.rst

.. _cloud_extensions:

Extensions
==========

To keep a standard Cloud installation for all customers and improve our ability to troubleshoot and provide support, we do not provide superuser access to Cloud clusters. Thus customers are not able to install PostgreSQL extensions themselves.

Generally there is no need to install extensions, however, because every Cloud cluster comes pre-loaded with many useful ones:

+--------------------+---------+------------+--------------------------------------------------------------------+
|        Name        | Version |   Schema   |                            Description                             |
+====================+=========+============+====================================================================+
| btree_gin          | 1.3     | public     | support for indexing common datatypes in GIN                       |
+--------------------+---------+------------+--------------------------------------------------------------------+
| btree_gist         | 1.5     | public     | support for indexing common datatypes in GiST                      |
+--------------------+---------+------------+--------------------------------------------------------------------+
| citext             | 1.6     | public     | data type for case-insensitive character strings                   |
+--------------------+---------+------------+--------------------------------------------------------------------+
| citus              | 9.5-1   | pg_catalog | Citus distributed database                                         |
+--------------------+---------+------------+--------------------------------------------------------------------+
| cube               | 1.4     | public     | data type for multidimensional cubes                               |
+--------------------+---------+------------+--------------------------------------------------------------------+
| dblink             | 1.2     | public     | connect to other PostgreSQL databases from within a database       |
+--------------------+---------+------------+--------------------------------------------------------------------+
| earthdistance      | 1.1     | public     | calculate great-circle distances on the surface of the Earth       |
+--------------------+---------+------------+--------------------------------------------------------------------+
| fuzzystrmatch      | 1.1     | public     | determine similarities and distance between strings                |
+--------------------+---------+------------+--------------------------------------------------------------------+
| hll                | 2.15    | public     | type for storing hyperloglog data                                  |
+--------------------+---------+------------+--------------------------------------------------------------------+
| hstore             | 1.7     | public     | data type for storing sets of (key, value) pairs                   |
+--------------------+---------+------------+--------------------------------------------------------------------+
| intarray           | 1.3     | public     | functions, operators, and index support for 1-D arrays of integers |
+--------------------+---------+------------+--------------------------------------------------------------------+
| ltree              | 1.2     | public     | data type for hierarchical tree-like structures                    |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_buffercache     | 1.3     | public     | examine the shared buffer cache                                    |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_cron            | 1.3     | public     | Job scheduler for PostgreSQL                                       |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_freespacemap    | 1.2     | public     | examine the free space map (FSM)                                   |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_partman         | 4.4.1   | partman    | Extension to manage partitioned tables by time or ID               |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_prewarm         | 1.2     | public     | prewarm relation data                                              |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_stat_statements | 1.8     | public     | track execution statistics of all SQL statements executed          |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pg_trgm            | 1.5     | public     | text similarity measurement and index searching based on trigrams  |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pgcrypto           | 1.3     | public     | cryptographic functions                                            |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pgrowlocks         | 1.2     | public     | show row-level locking information                                 |
+--------------------+---------+------------+--------------------------------------------------------------------+
| pgstattuple        | 1.5     | public     | show tuple-level statistics                                        |
+--------------------+---------+------------+--------------------------------------------------------------------+
| plpgsql            | 1.0     | pg_catalog | PL/pgSQL procedural language                                       |
+--------------------+---------+------------+--------------------------------------------------------------------+
| session_analytics  | 1.0     | public     |                                                                    |
+--------------------+---------+------------+--------------------------------------------------------------------+
| sslinfo            | 1.2     | public     | information about SSL certificates                                 |
+--------------------+---------+------------+--------------------------------------------------------------------+
| tablefunc          | 1.0     | public     | functions that manipulate whole tables, including crosstab         |
+--------------------+---------+------------+--------------------------------------------------------------------+
| topn               | 2.3.1   | public     | type for top-n JSONB                                               |
+--------------------+---------+------------+--------------------------------------------------------------------+
| unaccent           | 1.1     | public     | text search dictionary that removes accents                        |
+--------------------+---------+------------+--------------------------------------------------------------------+
| uuid-ossp          | 1.1     | public     | generate universally unique identifiers (UUIDs)                    |
+--------------------+---------+------------+--------------------------------------------------------------------+
| xml2               | 1.1     | public     | XPath querying and XSLT                                            |
+--------------------+---------+------------+--------------------------------------------------------------------+
