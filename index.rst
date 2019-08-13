Citus Documentation
===================

Welcome to the documentation for Citus 8.3! Citus horizontally scales PostgreSQL across commodity servers using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable real-time responses on large datasets.

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

   get_started/what_is_citus.rst
   get_started/tutorials.rst

.. toctree::
   :caption: Install
   :hidden:

   installation/single_machine.rst
   installation/multi_machine.rst
   installation/citus_cloud.rst

.. toctree::
   :caption: Use-Case Guides
   :hidden:

   use_cases/multi_tenant.rst
   use_cases/realtime_analytics.rst
   use_cases/timeseries.rst

.. toctree::
   :caption: Architecture
   :hidden:

   get_started/concepts.rst
   arch/mx.rst

.. toctree::
   :caption: Develop
   :hidden:

   develop/app_type.rst
   sharding/data_modeling.rst
   develop/migration.rst
   develop/reference.rst
   develop/api.rst
   develop/integrations.rst

.. toctree::
   :caption: Citus Cloud
   :hidden:

   cloud/getting_started.rst
   cloud/manage.rst
   cloud/additional.rst
   cloud/support.rst

.. toctree::
   :caption: Administer
   :hidden:

   admin_guide/cluster_management.rst
   admin_guide/table_management.rst
   admin_guide/upgrading_citus.rst

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

   articles/index.rst

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
.. image:: images/cloud-bill-credit.png
  :width: 0%
.. image:: images/cloud-bill-ach.png
  :width: 0%
