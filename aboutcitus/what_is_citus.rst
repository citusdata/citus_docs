What is Citus?
==============

Citus horizontally scales PostgreSQL across multiple machines using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable human real-time (less than a second) responses on large datasets.

Citus extends the underlying database rather than forking it, which gives developers and enterprises the power and familiarity of a traditional relational database. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

.. _when_to_use_citus:

When to Use Citus
-----------------

There are two situations where Citus particularly excels. The first is supporting real-time queries over large datasets. Commonly these queries occur in rapidly growing event systems or systems with time series data. Example use cases include:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Large dataset archival and reporting
* Analyzing sessions with funnel, segmentation, and cohort queries

Citus' benefits here are its ability to parallelize query execution and scale linearly with the number of worker databases in a cluster. However as analytical queries must aggregate data across a distributed system some up-front modeling is required for optimal performance and not all SQL guarantees can be enforced.

The second situation is managing the data for multi-tenant applications. These are applications where a single database cluster serves multiple tenants (typically companies), each of whose data is private from the other tenants. For a thorough overview of this type of application and its challenges, see Microsoft's paper `Multi-Tenant Data Architecture <https://msdn.microsoft.com/en-us/library/aa479086.aspx>`_. Citus uses the "shared schema" approach described in the paper, but isolates tenant information in separate shards. Citus routes individual tenant queries to the appropriate shard, where there is full-featured SQL support.

Existing schemas and queries typically require little adjustment during migration to the multi-tenant architecture. However the localized single-tenant queries lose the chance for parallelism found in the real-time use case. Additionally multi-tenant apps with few -- or very large -- tenants will not see a significant performance improvement.

For concrete examples check out our customer `use cases <https://www.citusdata.com/solutions/case-studies>`_.

Considerations for Use
----------------------

Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

Data models that have fewer tables (<10) work much better than those that have hundreds of tables. This is a property of distributed systems: the more tables, the more distributed dependencies.

For tools and SQL features, a good way to think about them is the following: if your workload aligns with use-cases noted in the :ref:`when_to_use_citus` section and you happen to run into an unsupported tool or query, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Workloads which require a large flow of information between worker nodes generally do not work as well. For instance:

* Traditional data warehousing with long, free-form SQL
* Many distributed transactions across multiple shards
* Queries that return data-heavy ETL results rather than summaries

These constraints come from the fact that Citus operates across many nodes (as compared to a single node database), giving you easy horizontal scaling as well as high availability.

.. raw:: html

  <script type="text/javascript">
  Intercom('trackEvent', 'docs-whatis-pageview');
  </script>
