What is Citus?
==============

Citus horizontally scales PostgreSQL across multiple machines using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable human real-time (less than a second) responses on large datasets.

Citus extends the underlying database rather than forking it, which gives developers and enterprises the power and familiarity of a traditional relational database. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

.. _when_to_use_citus:

When to Use Citus
-----------------

There are two situations where Citus particularly excels: real-time analytics and multi-tenant applications.

Real-Time Analytics
~~~~~~~~~~~~~~~~~~~

Citus supports real-time queries over large datasets. Commonly these queries occur in rapidly growing event systems or systems with time series data. Example use cases include:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Large dataset archival and reporting
* Analyzing sessions with funnel, segmentation, and cohort queries

Citus' benefits here are its ability to parallelize query execution and scale linearly with the number of worker databases in a cluster.

For concrete examples check out our customer `use cases <https://www.citusdata.com/solutions/case-studies>`_.

Multi-Tenant Applications
~~~~~~~~~~~~~~~~~~~~~~~~~

Another Citus use case is managing the data for multi-tenant applications. These are applications where a single database cluster serves multiple tenants (typically companies), each of whose data is private from the other tenants.

All tenants share a common schema and Citus distributes their data across shards. Citus routes individual tenant queries to the appropriate shard, each of which acts like a standalone database with full-featured SQL support.

This allows you to scale out your tenants across several machines and CPU cores, adding more memory and processing power for parallelism. Sharing a schema and cluster infrastructure among multiple tenants also uses hardware efficiently and reduces maintenance costs compared with a one-tenant-per-database instance model.

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
