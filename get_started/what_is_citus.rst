.. _what_is_citus:

What is Citus?
==============

Fast-growing `multi-tenant apps <https://www.citusdata.com/use-cases/multi-tenant-apps>`_ want to add new customers, deliver great performance, and not have to worry about database infrastructure. Data analysts want sub-second response times for customer-facing `analytics dashboards <https://www.citusdata.com/use-cases/real-time-analytics>`_, even with real-time ingestion, very large data sets, complex queries, and lots of concurrent users.

Citus allows these and other applications to enjoy the power and familiarity of a traditional relational database, but with the capability for massive scale. Applications connect to and use a Citus-enabled PostgreSQL database just like they would a traditional PostgreSQL database. Citus uses the :ref:`same SQL commands <citus_sql_reference>` that developers and frameworks already know.

+--------------------------------------------------------+-------------------------------------------------------------+
| Multi-Tenant Advantages                                | Real-Time Advantages                                        |
+========================================================+=============================================================+
| Fast queries for all tenants                           | Maintain sub-second responses as the dataset grows          |
+--------------------------------------------------------+-------------------------------------------------------------+
| Sharding logic in the database, not the application    | Analyze new events and new data as it happens, in real-time |
+--------------------------------------------------------+-------------------------------------------------------------+
| Hold more data than possible in single-node PostgreSQL | Parallelize SQL queries                                     |
+--------------------------------------------------------+-------------------------------------------------------------+
| Scale out without giving up SQL                        | Scale out without giving up SQL                             |
+--------------------------------------------------------+-------------------------------------------------------------+
| Maintain performance under high concurrency            | Maintain performance under high concurrency                 |
+--------------------------------------------------------+-------------------------------------------------------------+
| Fast metrics analysis across customer base             | Fast responses to dashboard queries                         |
+--------------------------------------------------------+-------------------------------------------------------------+
| Easily scale to handle new customer signups            | Use one database, not a patchwork                           |
+--------------------------------------------------------+-------------------------------------------------------------+
| Isolate resource usage of large and small customers    | Rich PostgreSQL data types and extensions                   |
+--------------------------------------------------------+-------------------------------------------------------------+

Citus is basically `worry-free Postgres <https://www.citusdata.com/product>`_ that is built to scale out. It's an extension to Postgres that :ref:`distributes data <distributed_arch>` and queries in a cluster of multiple machines. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

**Available in Three Ways:**

1. As `open source <https://www.citusdata.com/product/community>`_ to add to existing Postgres servers
2. On-premise with additional `enterprise grade <https://www.citusdata.com/product/enterprise>`_ security and cluster management tools
3. As a fully-managed database as a service, called `Citus Cloud <https://www.citusdata.com/product/cloud>`_

.. _how_big:

How Far Can Citus Scale?
------------------------

Citus scales horizontally by adding worker nodes, vertically by upgrading workers/coordinator, and supports switching to :ref:`mx` mode if needed. In practice our customers have achieved the following scale, with room to grow even more:

* `Algolia <https://www.citusdata.com/customers/algolia>`_
    * 5-10B rows ingested per day
* `Heap <https://www.citusdata.com/customers/heap>`_
    * 500+ billion events
    * 900TB of data on a 40-node Citus database cluster
* `Chartbeat <https://www.citusdata.com/customers/chartbeat>`_
    * >2.6B rows of data added per month
* `Pex <https://www.citusdata.com/customers/pex>`_
    * 30B rows updated/day
    * 20-node Citus database cluster on Google Cloud
    * 2.4TB memory, 1280 cores, and 60TB of data
    * ...with plans to grow to 45 nodes
* `Mixrank <https://www.citusdata.com/customers/mixrank>`_
    * 1600TB of time series data

For more customers and statistics, see our `customer stories <https://www.citusdata.com/customers#customer-index>`_.

.. _when_to_use_citus:

When to Use Citus
=================

Citus serves many use cases. Two common ones are scaling multi-tenant (B2B) databases and real-time analytics. In addition to the information below, there are examples of Citus `use-cases <https://www.citusdata.com/use-cases>`_ and `customer case studies <https://www.citusdata.com/solutions/case-studies>`_ on our main web site.

.. _mt_blurb:

Multi-Tenant Database
---------------------

Most B2B applications already have the notion of a tenant, customer, or account built into their data model. In this model, the database serves many tenants, each of whose data is separate from other tenants.

Citus provides full SQL coverage for this workload, and enables scaling out your relational database to 100K+ tenants. Citus also adds new features for multi-tenancy. For example, Citus supports tenant isolation to provide performance guarantees for large tenants, and has the concept of reference tables to reduce data duplication across tenants.

These capabilities allow you to scale out your tenants' data across many machines, and easily add more CPU, memory, and disk resources. Further, sharing the same database schema across multiple tenants makes efficient use of hardware resources and simplifies database management.

.. _rt_blurb:

Real-Time Analytics
-------------------

Citus supports real-time queries over large datasets. Commonly these queries occur in rapidly growing event systems or systems with time series data. Example use cases include:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Large dataset archival and reporting
* Analyzing sessions with funnel, segmentation, and cohort queries

Citus' benefits here are its ability to parallelize query execution and scale linearly with the number of worker databases in a cluster.

Considerations for Use
----------------------

Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

A good way to think about tools and SQL features is the following: if your workload aligns with use-cases described here and you happen to run into an unsupported tool or query, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Some workloads don't need a powerful distributed database, while others require a large flow of information between worker nodes. In the first case Citus is unnecessary, and in the second not generally performant. Here are some examples:

* When single-node Postgres can support your application and you do not expect to grow
* Offline analytics, without the need for real-time ingest nor real-time queries
* Analytics apps that do not need to support a large number of concurrent users
* Queries that return data-heavy ETL results rather than summaries

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'what-is-citus', section: 'about'});
  </script>
