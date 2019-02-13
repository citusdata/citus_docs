.. _data_migration:

Migrate Production Data
=======================

At this time, having updated the database schema and application queries to work with Citus, you're ready for the final step. It's time to migrate data to the Citus cluster and cut over the application to its new database.

The data migration path is dependent on downtime requirements and data size, but generally falls into one of the following two categories.

.. toctree::
   :maxdepth: 1

   migration_data_small.rst
   migration_data_big.rst
