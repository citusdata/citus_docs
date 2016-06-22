What is Citus?
==============

Citus horizontally scales PostgreSQL across multiple machines using sharding and replication. Its query engine parallelizes incoming SQL queries across these servers to enable human real-time (a.k.a. less than a second) responses on large datasets.

Citus extends the underlying database rather than forking it, which gives developers and enterprises the power and familiarity of a traditional relational database. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

When to Use Citus
-----------------

Example use cases:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events, including JOIN queries
* Aggregate reports on large archives
* Analyzing sessions with funnels, segmentation, and cohorts
* Extending a data warehouse with real-time capabilities

For concrete examples check out our customer `use cases <https://www.citusdata.com/solutions/case-studies>`_. Typical Citus workloads are operational, with aggregate queries and no long-lived transactions.

Considerations for Use
----------------------

Although Citus extends PostgreSQL with distributed functionality, it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

Data models that have fewer tables (<10) work much better than those that have hundreds of tables. This is a property of distributed systems: the more tables, the more distributed dependencies.

A good way to think about tool and SQL feature coverage is the following: if your workload aligns with use-cases noted in the "When to use Citus" section and you happen to run into an unsupported query or tool, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Workloads which require a large (non-aggregated) flow of information between nodes generally do not work as well. For instance:

* Traditional data warehousing with long, free-form SQL
* Distributed transactions across multiple shards
* Queries that return data-heavy ETL results rather than summaries

These constraints come from the fact that we operate across many nodes (as compared to a single node database), giving you easy horizontal scaling as well as high availability.
