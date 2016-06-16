Citus Documentation
====================

Welcome to the documentation for Citus 5.1! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

The documentation explains how you can install Citus and then provides
instructions to design, build, query, and maintain your Citus cluster. It also
includes a Reference section which provides quick information on several
topics.

.. toctree::
   :glob:
   :caption: About Citus

   aboutcitus/what_is_citus.rst
   aboutcitus/introduction_to_citus.rst

.. toctree::
   :caption: Tutorials

   tutorials/tut-cluster.rst
   tutorials/tut-real-time.rst
   tutorials/tut-user-data.rst

.. toctree::
   :caption: Installation

   installation/requirements.rst
   installation/development.rst
   installation/production.rst

.. toctree::
   :maxdepth: 1
   :caption: Distributed Tables

   dist_tables/working_with_distributed_tables.rst
   dist_tables/append_distribution.rst
   dist_tables/hash_distribution.rst
   dist_tables/querying.rst
   dist_tables/postgresql_extensions.rst

.. toctree::
   :maxdepth: 1
   :caption: Data Manipulation

   dml/updating_deleting.rst

.. toctree::
   :caption: Performance

   performance/query_processing.rst
   performance/scaling_data_ingestion.rst
   performance/performance_tuning.rst

.. toctree::
   :maxdepth: 1
   :caption: Administration

   admin_guide/cluster_management.rst
   admin_guide/upgrading_citus.rst
   admin_guide/transitioning_from_postgresql_to_citus.rst

.. toctree::
   :caption: Reference

   reference/citus_sql_reference.rst
   reference/user_defined_functions.rst
   reference/metadata_tables.rst
   reference/configuration.rst
