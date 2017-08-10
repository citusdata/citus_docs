Citus Documentation
====================

Welcome to the documentation for Citus 6.2! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

.. raw:: html

  <div class="row">
    <div class="col-xs-4">
      <div class="box">
        <h3>Overview</h3>
        <img src="_images/ico1.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
    </div>
    <div class="col-xs-4">
      <div class="box">
        <h3>Getting Started</h3>
        <img src="_images/ico2.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
    </div>
    <div class="col-xs-4">
      <div class="box">
        <h3>Awesome Stuff</h3>
        <img src="_images/ico3.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
    </div>
  </div>
  <div class="row">
    <div class="col-xs-4">
      <div class="box">
        <h3>Total Mastery</h3>
        <img src="_images/ico4.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
    </div>
    <div class="col-xs-4">
      <div class="box">
        <h3>Beyond Infinity</h3>
        <img src="_images/ico5.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
    </div>
    <div class="col-xs-4">
      <div class="box">
        <h3>Transcendence</h3>
        <img src="_images/ico6.png" />
        <p>Ignota autem nostrud albucius sagittis no fabulas erat eam ridens et per moderatius 98 movet? Sea iure est integre metus adipisci justo id con ultrices omnes minim odioaccommodare. Consul omnium enim volumus lectus habeo fuisset pri utinam sem tamquam no.</p>
      </div>
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

   cloud/index.rst
   cloud/availability.rst
   cloud/security.rst
   cloud/scaling.rst
   cloud/logging.rst
   cloud/monitoring.rst
   cloud/forking.rst
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

.. image:: images/demo/ico1.png
  :width: 0%
.. image:: images/demo/ico2.png
  :width: 0%
.. image:: images/demo/ico3.png
  :width: 0%
.. image:: images/demo/ico4.png
  :width: 0%
.. image:: images/demo/ico5.png
  :width: 0%
.. image:: images/demo/ico6.png
  :width: 0%

.. raw:: html

  <script type="text/javascript">
  setTimeout(function(){var a=document.createElement("script");
  var b=document.getElementsByTagName("script")[0];
  a.src=document.location.protocol+"//script.crazyegg.com/pages/scripts/0052/6282.js?"+Math.floor(new Date().getTime()/3600000);
  a.async=true;a.type="text/javascript";b.parentNode.insertBefore(a,b)}, 1);
  </script>
