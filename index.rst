Citus Documentation
====================

Welcome to the documentation for Citus 7.0! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

.. raw:: html

  <div class="front-menu row">
    <div class="col-xs-4">
      <a class="box" href="portals/getting_started.html">
        <h3>Getting Started</h3>
        <img src="_images/number-one.png" />
        Learn the Citus architecture, install locally,
        and follow some ten-minute tutorials.
      </a>
    </div>
    <div class="col-xs-4">
      <a class="box" href="portals/use_cases.html">
        <h3>Use Cases</h3>
        <img src="_images/use-cases.png" />
        See how Citus allows multi-tenant applications
        to scale with minimal database changes.
      </a>
    </div>
    <div class="col-xs-4">
      <a class="box" href="portals/migrating.html">
        <h3>Migrating to Citus</h3>
        <img src="_images/migrating.png" />
        Move from plain PostgreSQL to Citus, and discover
        data modeling techniques for distributed systems.
      </a>
    </div>
  </div>
  <div class="front-menu row">
    <div class="col-xs-4">
      <a class="box" href="portals/citus_cloud.html">
        <h3>Citus Cloud</h3>
        <img src="_images/cloud.png" />
        Explore our secure, scalable, highly available
        database-as-a-service.
      </a>
    </div>
    <div class="col-xs-4">
      <a class="box" href="portals/reference.html">
        <h3>API / Reference</h3>
        <img src="_images/reference.png" />
        Get the most out of Citus by learning its
        functions and configuration.
      </a>
    </div>
    <div class="col-xs-4">
      <a class="box" href="portals/support.html">
        <h3>Help and Support</h3>
        <img src="_images/help.png" />
        See the frequently asked questions, and
        contact us. This is the page to get unstuck.
      </a>
    </div>
  </div>

.. toctree::
   :glob:
   :caption: About Citus
   :hidden:

   aboutcitus/what_is_citus.rst
   aboutcitus/introduction_to_citus.rst

.. toctree::
   :caption: Installation
   :hidden:

   installation/requirements.rst
   installation/development.rst
   installation/production.rst

.. toctree::
   :caption: Tutorial
   :hidden:

   tutorials/multi-tenant-tutorial.rst
   tutorials/real-time-analytics-tutorial.rst
   tutorials/faceted-search.rst

.. toctree::
   :caption: Distributed Data Modeling
   :hidden:

   sharding/data_modeling.rst
   sharding/colocation.rst

.. toctree::
   :maxdepth: 1
   :caption: Distributed Tables
   :hidden:

   dist_tables/ddl.rst
   dist_tables/dml.rst
   dist_tables/querying.rst
   dist_tables/extensions.rst

.. toctree::
   :caption: Transitioning to Citus
   :hidden:

   migration/transitioning.rst

.. toctree::
   :caption: Performance
   :hidden:

   performance/query_processing.rst
   performance/scaling_data_ingestion.rst
   performance/performance_tuning.rst

.. toctree::
   :maxdepth: 1
   :caption: Cloud
   :hidden:

   cloud/why.rst
   cloud/availability.rst
   cloud/security.rst
   cloud/scaling.rst
   cloud/logging.rst
   cloud/monitoring.rst
   cloud/mx.rst
   cloud/support.rst

.. toctree::
   :caption: Use-Case Guides
   :hidden:

   use_case_guide/multi_tenant.rst
   use_case_guide/real_time_dashboards.rst

.. toctree::
   :maxdepth: 1
   :caption: Administration
   :hidden:

   admin_guide/cluster_management.rst
   admin_guide/table_management.rst
   admin_guide/production_sizing.rst
   admin_guide/upgrading_citus.rst

.. toctree::
   :caption: Reference
   :hidden:

   reference/citus_sql_reference.rst
   reference/sql_workarounds.rst
   reference/user_defined_functions.rst
   reference/metadata_tables.rst
   reference/configuration.rst
   reference/append.rst

.. toctree::
   :caption: FAQ
   :hidden:

   faq/faq.rst

.. Declare these images as dependencies so that
.. sphinx copies them. It can't detect them in
.. the embedded raw html

.. image:: images/icons/number-one.png
  :width: 0%
.. image:: images/icons/use-cases.png
  :width: 0%
.. image:: images/icons/migrating.png
  :width: 0%
.. image:: images/icons/cloud.png
  :width: 0%
.. image:: images/icons/reference.png
  :width: 0%
.. image:: images/icons/help.png
  :width: 0%

.. raw:: html

  <script type="text/javascript">
  setTimeout(function(){var a=document.createElement("script");
  var b=document.getElementsByTagName("script")[0];
  a.src=document.location.protocol+"//script.crazyegg.com/pages/scripts/0052/6282.js?"+Math.floor(new Date().getTime()/3600000);
  a.async=true;a.type="text/javascript";b.parentNode.insertBefore(a,b)}, 1);
  </script>
