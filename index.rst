Citus Documentation
====================

Welcome to the documentation for Citus 5.2! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

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
   tutorials/tut-hash-distribution.rst
   tutorials/tut-append-distribution.rst

.. toctree::
   :caption: Installation

   installation/requirements.rst
   installation/development.rst
   installation/production.rst

.. toctree::
   :maxdepth: 1
   :caption: Distributed Tables

   dist_tables/working_with_distributed_tables.rst
   dist_tables/hash_distribution.rst
   dist_tables/append_distribution.rst
   dist_tables/querying.rst
   dist_tables/postgresql_extensions.rst

.. toctree::
   :caption: Performance

   performance/query_processing.rst
   performance/scaling_data_ingestion.rst
   performance/performance_tuning.rst

.. toctree::
   :maxdepth: 1
   :caption: Cloud

   cloud/index.rst
   cloud/features.rst
   cloud/support.rst

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

.. toctree::
   :caption: FAQ

   faq/faq.rst

.. raw:: html

  <script type="text/javascript">
  setTimeout(function(){var a=document.createElement("script");
  var b=document.getElementsByTagName("script")[0];
  a.src=document.location.protocol+"//script.crazyegg.com/pages/scripts/0052/6282.js?"+Math.floor(new Date().getTime()/3600000);
  a.async=true;a.type="text/javascript";b.parentNode.insertBefore(a,b)}, 1);
  </script>
