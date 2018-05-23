Migrating an Existing App
#########################

.. _transitioning_mt:

Migrating an existing relational store to Citus sometimes requires adjusting the schema and queries for optimal performance. Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

.. toctree::
  :maxdepth: 2

  migration_mt_schema.rst
  migration_mt_query.rst
  migration_mt_ror.rst
  migration_mt_django.rst
  migration_mt_asp.rst
  migration_data.rst
  migration_rt.rst
