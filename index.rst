Citus Documentation
===================

Welcome to the documentation for Citus 11 (Beta)! Citus is an open source extension
to PostgreSQL that transforms Postgres into a distributed database. To scale
out Postgres horizontally, Citus employs distributed tables, reference tables,
and a distributed SQL query engine. The query engine parallelizes SQL queries
across multiple servers in a database cluster to deliver dramatically improved
query response times, even for data-intensive applications.

.. raw:: html

  <div class="front-menu row">
    <div class="col-md-4">
      <a class="box" href="portals/getting_started.html">
        <h3>Getting Started</h3>
        <img src="_images/number-one.png" role="presentation" alt="" />
        Learn the Citus architecture, install locally,
        and follow some ten-minute tutorials.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/use_cases.html">
        <h3>Use Cases</h3>
        <img src="_images/use-cases.png" role="presentation" alt="" />
        See how Citus allows multi-tenant applications
        to scale with minimal database changes.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/migrating.html">
        <h3>Migrating to Citus</h3>
        <img src="_images/migrating.png" role="presentation" alt="" />
        Move from plain PostgreSQL to Citus, and discover
        data modeling techniques for distributed systems.
      </a>
    </div>
  </div>
  <div class="front-menu row">
    <div class="col-md-4">
      <a class="box" href="portals/citus_cloud.html">
        <h3>Managed Service</h3>
        <img src="_images/cloud.png" role="presentation" alt="" />
        Explore our secure, scalable, highly available
        database-as-a-service.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/reference.html">
        <h3>API / Reference</h3>
        <img src="_images/reference.png" role="presentation" alt="" />
        Get the most out of Citus by learning its
        functions and configuration.
      </a>
    </div>
    <div class="col-md-4">
      <a class="box" href="portals/support.html">
        <h3>Help and Support</h3>
        <img src="_images/help.png" role="presentation" alt="" />
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

   installation/single_node.rst
   installation/multi_node.rst
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
