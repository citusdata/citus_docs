.. _distributed_ddl_and_dml:

Distributed DDL and DML
#######################

CitusDB provides distributed functionality by extending PostgreSQL using the hook and extension APIs. This allows users to benefit from the features that come with the rich PostgreSQL ecosystem. These features include, but aren’t limited to, support for a wide range of `data types <http://www.postgresql.org/docs/9.4/static/datatype.html>`_ (including semi-structured data types like jsonb and hstore), `operators and functions <http://www.postgresql.org/docs/9.4/static/functions.html>`_, full text search, and other extensions such as `PostGIS <http://postgis.net/>`_ and `HyperLogLog <https://github.com/aggregateknowledge/postgresql-hll>`_. Further, proper use of the extension APIs enable full compatibility with standard PostgreSQL tools such as `pgAdmin <http://www.pgadmin.org/>`_, `pg_backup <http://www.postgresql.org/docs/9.4/static/backup.html>`_, and `pg_upgrade <http://www.postgresql.org/docs/9.4/static/pgupgrade.html>`_.

CitusDB users can leverage standard PostgreSQL interfaces with no or minimal modifications. This includes commands for creating tables, loading data, updating rows, and also for querying. You can find a full reference of the PostgreSQL constructs `here <http://www.postgresql.org/docs/9.4/static/sql-commands.html>`_. We also discuss the relevant commands in our documentation as needed. Before we dive into the syntax for these commands, we briefly discuss two important concepts which must be decided during schema creation: the distribution column and distribution method.

.. toctree::
   :hidden:
   
   distribution_column.rst
   distribution_method.rst
   append_distribution.rst
   hash_distribution.rst
   range_distribution.rst





