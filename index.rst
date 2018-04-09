Citus Documentation
===================

Welcome to the documentation for Citus 7.3! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

.. raw:: html

  <div class="front-menu row">
    <div class="col-md-4">
      <a class="box" href="portals/getting_started.html">
        <h3>Getting Started</h3>
        <img src="_images/number-one.png" />
        Learn the Citus architecture, install locally,
        and follow some ten-minute tutorials.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/use_cases.html">
        <h3>Use Cases</h3>
        <img src="_images/use-cases.png" />
        See how Citus allows multi-tenant applications
        to scale with minimal database changes.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/migrating.html">
        <h3>Migrating to Citus</h3>
        <img src="_images/migrating.png" />
        Move from plain PostgreSQL to Citus, and discover
        data modeling techniques for distributed systems.
      </a>
    </div>
  </div>
  <div class="front-menu row">
    <div class="col-md-4">
      <a class="box" href="portals/citus_cloud.html">
        <h3>Citus Cloud</h3>
        <img src="_images/cloud.png" />
        Explore our secure, scalable, highly available
        database-as-a-service.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/reference.html">
        <h3>API / Reference</h3>
        <img src="_images/reference.png" />
        Get the most out of Citus by learning its
        functions and configuration.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/support.html">
        <h3>Help and Support</h3>
        <img src="_images/help.png" />
        See the frequently asked questions, and
        contact us. This is the page to get unstuck.
      </a>
    </div>
  </div>

.. toctree::
   :caption: Get Started
   :hidden:

   00get_started/what_is_citus.rst
   00get_started/concepts.rst
   00get_started/tutorials.rst

.. toctree::
   :caption: Install
   :hidden:

   admin_guide/installation_single_node.rst
   admin_guide/installation_multi_node.rst
   admin_guide/installation_cloud.rst

.. toctree::
   :caption: Use-Case Guides
   :hidden:

   00use_cases/mt.rst
   00use_cases/rt.rst
   00use_cases/timeseries.rst

.. toctree::
   :caption: Develop
   :hidden:

   00develop/app_type.rst
   sharding/data_modeling.rst
   00develop/migration.rst
   migration/data.rst
   00develop/reference.rst
   00develop/api.rst

.. toctree::
   :caption: Administer
   :hidden:

   admin_guide/cluster_management.rst
   admin_guide/table_management.rst
   admin_guide/upgrading_citus.rst

.. toctree::
   :caption: Cloud
   :hidden:

   cloud/getting_started.rst
   cloud/00manage.rst
   cloud/additional.rst
   cloud/support.rst

.. toctree::
   :caption: Troubleshoot
   :hidden:

   performance/performance_tuning.rst
   admin_guide/diagnostic_queries.rst
   reference/common_errors.rst

.. toctree::
   :caption: FAQ
   :hidden:

   faq/faq.rst

.. toctree::
   :caption: Articles
   :hidden:

   articles/heroku_addon.rst
   articles/efficient_rollup.rst
   articles/hll_count_distinct.rst
   articles/scale_on_aws.rst
   articles/parallel_indexing.rst
   articles/aggregation.rst
   articles/outer_joins.rst
   articles/designing_saas.rst
   articles/metrics_dashboard.rst
   articles/sharding_mt_app.rst
   articles/semi_structured_data.rst
   articles/faceted_search.rst

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
.. image:: images/logo.png
  :width: 0%

.. raw:: html

  <script type="text/javascript">
  setTimeout(function(){var a=document.createElement("script");
  var b=document.getElementsByTagName("script")[0];
  a.src=document.location.protocol+"//script.crazyegg.com/pages/scripts/0052/6282.js?"+Math.floor(new Date().getTime()/3600000);
  a.async=true;a.type="text/javascript";b.parentNode.insertBefore(a,b)}, 1);
  </script>
