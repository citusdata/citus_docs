.. _what_is_citus:

What is Citus?
==============

The Citus database is an open source extension to Postgres that gives you all the greatness of Postgres, at any scale—from a single node to a large distributed database cluster. Because Citus is an extension (not a fork)
to Postgres, when you use Citus, you are also using Postgres. You can leverage
the latest Postgres features, tooling, and ecosystem.

With Citus you get distributed Postgres features like
sharding, distributed tables, reference tables, a distributed query engine, columnar storage—and as of Citus 11.0, the ability to query from any node.
The Citus combination of parallelism, keeping more data in memory, and higher
I/O bandwidth can lead to significant performance improvements for multi-tenant
SaaS applications, customer-facing real-time analytics dashboards, and time
series workloads.

**Two Ways to Get Citus:**

1. **Open source**: Citus is 100% open source. You can `download Citus <https://www.citusdata.com/download/>`_
   open source, or to see the source code and build it yourself, visit the `Citus repo <https://github.com/citusdata/citus>`_
   on GitHub.
2. **Managed service**: The Citus database is available as a managed service in the cloud with `Azure Cosmos DB for PostgreSQL
   <https://learn.microsoft.com/azure/cosmos-db/postgresql/introduction/>`_, formerly known as Hyperscale (Citus) in Azure Database for PostgreSQL.

.. _how_big:

Citus Gives You Postgres At Any Scale
-------------------------------------

You can start using Citus on a single node, using a distributed data model from the beginning so you are "scale out ready". When your Postgres workload needs to scale, it's easy to add worker nodes to the Citus database cluster, and/or to scale up the coordinator and worker nodes in your cluster. 

Sometimes people ask "how big can Citus scale?" Here are a few examples of large-scale customers—but please keep in mind that there are many, many 2-node and 3-node Citus clusters in the wild, too.

* `Algolia <https://www.citusdata.com/customers/algolia>`_

  * 5-10B rows ingested per day

* `Heap <https://www.citusdata.com/customers/heap>`_

  * 700+ billion events
  * 1.4PB of data on a 100-node Citus database cluster

* `Pex <https://www.citusdata.com/customers/pex>`_

  * 80B rows updated/day
  * 20-node Citus database cluster
  * 2.4TB memory, 1280 cores, and 80TB of data
  * ...with plans to grow to 45 nodes

* `MixRank <https://www.citusdata.com/customers/mixrank>`_

  * 10 PB of time series data

For more customers and statistics, see our `customer stories <https://www.citusdata.com/customers#customer-index>`_.

.. _when_to_use_citus:

When to Use Citus
=================

.. _mt_blurb:

Multi-Tenant SaaS Database
--------------------------

Most B2B applications already have the notion of a tenant, customer, or account built into their data model. In this model, the database serves many tenants, each of whose data is separate from other tenants.

Citus provides full SQL coverage for this workload, and enables scaling out your relational database to 100K+ tenants. Citus also adds new features for multi-tenancy. For example, Citus supports tenant isolation to provide performance guarantees for large tenants, and has the concept of reference tables to reduce data duplication across tenants.

These capabilities allow you to scale out your tenants' data across many machines, and easily add more CPU, memory, and disk resources. Further, sharing the same database schema across multiple tenants makes efficient use of hardware resources and simplifies database management.

Some advantages of Citus for multi-tenant applications:

* Fast queries for all tenants
* Sharding logic in the database, not the application
* Hold more data than possible in single-node PostgreSQL
* Scale out without giving up SQL
* Maintain performance under high concurrency
* Fast metrics analysis across customer base
* Easily scale to handle new customer signups
* Isolate resource usage of large and small customers

.. _rt_blurb:

Real-Time Analytics
-------------------

Citus supports real-time queries over large datasets. Commonly these queries occur in rapidly growing event systems or systems with time series data. Example use cases include:

* Analytic dashboards with subsecond response times
* Exploratory queries on unfolding events
* Large dataset archival and reporting
* Analyzing sessions with funnel, segmentation, and cohort queries

Citus' benefits here are its ability to parallelize query execution and scale linearly with the number of worker databases in a cluster. Some advantages of Citus for real-time applications:

* Maintain sub-second responses as the dataset grows
* Analyze new events and new data as it happens, in real-time
* Parallelize SQL queries
* Scale out without giving up SQL
* Maintain performance under high concurrency
* Fast responses to dashboard queries
* Use one database, not a patchwork
* Rich PostgreSQL data types and extensions

.. _ms_blurb:

Microservices
-------------

Citus supports schema based sharding, which allows distributing regular database schemas across many machines. This sharding methodology fits nicely with typical Microservices architecture, where storage is fully owned by the service hence can't share the same schema definition with other tenants.

Schema based sharding is an easier model to adopt, create a new schema and just set the `search_path` in your service and you're ready to go.

Advantages of using Citus for microservices:

* Allows distributing horizontally scalable state across services, solving one of the `main problems <https://stackoverflow.blog/2020/11/23/the-macro-problem-with-microservices/>`_ of microservices
* Ingest strategic business data from microservices into common distributed tables for analytics
* Efficiently use hardware by balancing services on multiple machines
* Isolate noisy services to their own nodes
* Easy to understand sharding model
* Quick adoption

Considerations for Use
----------------------

Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

A good way to think about tools and SQL features is the following: if your workload aligns with use-cases described here and you happen to run into an unsupported tool or query, then there’s usually a good workaround.

When Citus is Inappropriate
---------------------------

Some workloads don't need a powerful distributed database, while others require a large flow of information between worker nodes. In the first case Citus is unnecessary, and in the second not generally performant. Here are some examples:

* When you do not expect your workload to ever grow beyond a single Postgres node
* Offline analytics, without the need for real-time ingest nor real-time queries
* Analytics apps that do not need to support a large number of concurrent users
* Queries that return data-heavy ETL results rather than summaries
