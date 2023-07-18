Migrating an Existing App
#########################

.. _transitioning_mt:

Migrating an existing application to Citus sometimes requires adjusting the schema and queries for optimal performance. Citus extends PostgreSQL with distributed functionality, but :ref:`row_based_sharding` is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

There is another mode of operation in Citus called :ref:`schema_based_sharding`, and while :ref:`row_based_sharding` results in best performance and hardware efficiency, see schema based sharding if you are in a need for a more drop-in approach.

The first steps are to optimize the existing database schema so that it can work efficiently across multiple computers.

.. toctree::
  :maxdepth: 2

  migration_mt_schema.rst

Next, update application code and queries to deal with the schema changes.

.. toctree::
  :maxdepth: 2

  migration_mt_query.rst

After testing the changes in a development environment, the last step is to migrate production data to a Citus cluster and switch over the production app. We have techniques to minimize downtime for this step.

.. toctree::
  :maxdepth: 2

  migration_data.rst
