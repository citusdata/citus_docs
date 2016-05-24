What is Citus?
==============

Citus horizontally scales PostgreSQL across multiple machines using sharding and replication. It works well when you have a large data set and when you want to get answers from that data in human real-time – typically in less than a second.

Citus extends the underlying database rather than forking it, which gives developers and enterprises the power and familiarity of a traditional relational database. As an extension, Citus supports new PostgreSQL releases, allowing users to benefit from new features while maintaining compatibility with existing PostgreSQL tools.

When to Use Citus
-----------------

Example use cases:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Aggregate reports on large archives
* Analyzing sessions with funnels, segmentation, and cohorts
* Extending a data warehouse with real-time capabilities

For concrete examples check out our customer `use cases <https://www.citusdata.com/solutions/case-studies>`_. Typical Citus workloads are operational, with aggregate queries and no long-lived transactions.

Considerations for Use
----------------------

Although Citus extends PostgreSQL with distributed functionality, it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

Data models that have fewer tables (<10) work much better than those that have hundreds of tables. This is a property of distributed systems: the more tables, the more distributed dependencies. Still, compared with NoSQL databases Citus does not require aggressive denormalization.

Citus supports most PostgreSQL tools. Still users may need to take additional steps when using tools that require distributed execution. For example, pg_dump and pg_restore currently don’t take distributed backups, but there are scripted ways to make these tools work on individual PostgreSQL nodes.

PostgreSQL provides thousands of features, and Citus doesn’t yet scale them all. A good way to think about feature coverage is the following: if your workload aligns with use-cases noted in the “When to use Citus” section and you happen to run into an unsupported query, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Workloads which require a large (non-aggregated) flow of information between nodes generally do not work as well. For instance:

* Traditional data warehousing with long, free-form SQL
* Distributed transactions across multiple shards
* Queries that return data-heavy ETL results rather than summaries

These constraints come from the fact that we operate across many nodes (as compared to a single node database), giving you easy horizontal scaling as well as high availability.
