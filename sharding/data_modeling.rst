.. _distributed_data_modeling:

Distributed modeling refers to choosing how to distribute and query information across nodes in a multi-machine database cluster. There are common use cases for a distributed database with well understood design tradeoffs. It will be helpful for you to identify whether your application falls into one of these categories and in order to know what features and performance to expect.

Multi-Tenant Applications
-------------------------

Whether you’re building marketing analytics, a portal for e-commerce sites, or an application to cater to schools, if you’re building an application and your customer is another business then a multi-tenant approach is the norm. The same code runs for all customers, but each customer sees their own private data set, except in some cases of holistic internal reporting.

Early in your application’s life customer data has a simple structure which evolves organically. Typically all information relates to a central customer/user/tenant table. With a smaller amount of data (10s of GBs) it’s easy to scale the application by throwing more hardware at it, but what happens when you’ve had enough success that your data no longer fits in memory on a single box, or you need more concurrency? This is where a distributed database helps. You can store customer data on multiple machines.

Except for internal site-wide analytics, most queries in a multi-tenant scenario involve data from one tenant at a time. Tenants do not cross-reference each other's information. Thus by keeping each tenant's data contained within a single node you can route SQL queries to that node and run them there, which keeps operations like JOINs fast because of the co-located data.

The technical advantages for keeping each tenant's information together on a distinct node and routing queries to the node are full SQL support and ease of data migration. Each query runs on a single machine which appears like a regular standalone PostgreSQL database. There are no issues shuffling information across nodes, no distributed transaction semantics or network overhead. All queries that work and are efficient on a single machine will continue to work without modification.

However the multi-tenant architecture ofers less less capability for parallelism. Certainly when there are few tenants there can be only few machines to service them. Additionally if some tenants are extraordinarily large compared with others then the nodes for the large tenants will experience higher load and be unable to share the work across less utilized nodes.


Real-time Analytics
-------------------

Many companies use real-time analytics. Events such as website clicks or sensor measurements come in at a high rate and users want real-time insight into this data using a dashboard. Distributing data evenly across the nodes in a distributed database allows massively parallel processing for SQL queries.

Like the multi-tenant use case this allows dynamic scalability on commodity hardware with ability to easily add or remove nodes. Unlike the the multi-tenant use case it requires greater care to (re)write queries to minimize network overhead between nodes.

Foo!

Massively parallel processing for powerful SQL analytics
Real-time inserts/updates on distributed database tables

JSON and structured data in one database
PostgreSQL expressiveness and familiarity

Whereas the multi-tenant use case supports rich SQL with limited parallelism, the realtime analytics case requires 

How to Distribute Data
----------------------

In every table in Citus you must choose exactly one column which as the "distribution column." This informs the database to maintain statistics about the distribution column in each shard. Citus’s distributed query optimizer then leverages these statistics to determine how best a query should be executed.

Typically, you should choose that column as the distribution column which is the most commonly used join key or on which most queries have filters. For filters, Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column, then Citus executes the join only between those shards which have matching / overlapping distribution column ranges. This helps in greatly reducing both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps Citus push down several operations directly to the worker shards, hence reducing network I/O.

.. note::
  Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

Use Cases and Tradeoffs
-----------------------

The best choice of distribution column varies depending on the use case and queries. Two common scenarios are the multi-tenant B2B application and the realtime analytics dashboard. Both cases involve tradeoffs.

Multi-Tenant
~~~~~~~~~~~~

* ✔ SQL Coverage
* ✔ Ease of Migration
* ✘ Less Parallelism
* ✘ Less effective for large (or few) tenants

In the multi-tenant use case all tables include a tenant id and are distributed by it. When SQL queries are restricted to accessing data about a single tenant then Citus can execute them within a single shard. Having all data colocated in a shard is efficient and supports all SQL features. However running queries on a single shard limits the ability to parallelize execution.

Existing schemas and queries typically require little adjustment during migration to the multi-tenant architecture. Additionally multi-tenant apps with few (or very large) tenants will not see a significant performance improvement.

Real-Time Analytics
~~~~~~~~~~~~~~~~~~~

* ✔ Parallelism
* ✔ Linear Scalability
* ✘ Reduced SQL Coverage
* ✘ Upfront Data Modeling

The other common option, realtime analytics, distributes by another column (such as user id). The queries in this scenario typically request aggregate information from multiple shards. This permits query parallelism but restricts some of the SQL features available, due to the constraints of being a distributed system.

As analytical queries must move data across the cluster, some up-front modeling is required for optimal performance and not all SQL guarantees can be enforced.
