.. _what_is_citus:

Why Citus?
==========

Fast-growing multi-tenant apps want to add new customers, deliver great performance, and not have to worry about database infrastructure. Data analysts want sub-second response times for customer-facing analytics dashboards, even with real-time ingestion, very large data sets, complex queries, and lots of concurrent users.

Citus allows these and other applications to enjoy the power and familiarity of a traditional relational database, but with the capability for massive scale. Applications connect to and use a Citus-enabled PostgreSQL database just like they would a traditional PostgreSQL database. Citus uses the same SQL commands that developers and frameworks already know.

What is it?
-----------

Citus is basically worry-free Postgres that is built to scale out. It's an extension to Postgres that distributes data and queries in a cluster of multiple machines. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

Citus is available in three ways:

1. As open source to add to existing Postgres servers
2. As enterprise software with additional features
3. As a fully-managed database as a service, called Citus Cloud

.. _when_to_use_citus:

When to Use Citus
=================

Citus serves many use cases. Two common ones are scaling multi-tenant (B2B) databases and real-time analytics.

.. _mt_blurb:

Multi-Tenant Database
~~~~~~~~~~~~~~~~~~~~~

Most B2B applications already have the notion of a tenant, customer, or account built into their data model. In this model, the database serves many tenants, each of whose data is separate from other tenants.

Citus provides full SQL coverage for this workload, and enables scaling out your relational database to 100K+ tenants. Citus also adds new features for multi-tenancy. For example, Citus supports tenant isolation to provide performance guarantees for large tenants, and has the concept of reference tables to reduce data duplication across tenants.

These capabilities allow you to scale out your tenants' data across many machines, and easily add more CPU, memory, and disk resources. Further, sharing the same database schema across multiple tenants makes efficient use of hardware resources and simplifies database management.

.. _rt_blurb:

Real-Time Analytics
~~~~~~~~~~~~~~~~~~~

Citus supports real-time queries over large datasets. Commonly these queries occur in rapidly growing event systems or systems with time series data. Example use cases include:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Large dataset archival and reporting
* Analyzing sessions with funnel, segmentation, and cohort queries

Citus' benefits here are its ability to parallelize query execution and scale linearly with the number of worker databases in a cluster.

For concrete examples check out our customer `use cases <https://www.citusdata.com/solutions/case-studies>`_.

Considerations for Use
----------------------

Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

A good way to think about tools and SQL features is the following: if your workload aligns with use-cases noted in the :ref:`when_to_use_citus` section and you happen to run into an unsupported tool or query, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Workloads which require a large flow of information between worker nodes generally do not work as well. For instance:

* Traditional data warehousing with long, free-form SQL
* Many distributed transactions across multiple shards
* Queries that return data-heavy ETL results rather than summaries

These constraints come from the fact that Citus operates across many nodes (as compared to a single node database), giving you easy horizontal scaling as well as high availability.

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'what-is-citus', section: 'about'});
  </script>
