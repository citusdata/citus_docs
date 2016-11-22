.. _distributed_data_modeling:

Distributed modeling refers to choosing how to distribute information across nodes in a multi-machine database cluster and query it efficiently. There are common use cases for a distributed database with well understood design tradeoffs. It will be helpful for you to identify whether your application falls into one of these categories in order to know what features and performance to expect.

Multi-Tenant Applications
-------------------------

Whether you’re building marketing analytics, a portal for e-commerce sites, or an application to cater to schools, if you’re building an application and your customer is another business then a multi-tenant approach is the norm. The same code runs for all customers, but each customer sees their own private data set, except in some cases of holistic internal reporting.

Early in your application’s life customer data has a simple structure which evolves organically. Typically all information relates to a central customer/user/tenant table. With a smaller amount of data (10s of GBs) it’s easy to scale the application by throwing more hardware at it, but what happens when you’ve had enough success that your data no longer fits in memory on a single box, or you need more concurrency? This is where a distributed database helps. You can store customer data on multiple machines.

Except for internal site-wide analytics, most queries in a multi-tenant scenario involve data from one tenant at a time. Tenants do not cross-reference each other's information. Thus by keeping each tenant's data contained within a single node you can route SQL queries to that node and run them there, which keeps operations like JOINs fast because of the co-located data.

The technical advantages for keeping each tenant's information together on a distinct node and routing queries to the node are full SQL support and ease of data migration. Each query runs on a single machine which appears like a regular standalone PostgreSQL database. There are no issues shuffling information across nodes, no distributed transaction semantics or network overhead. All queries that work and are efficient on a single machine will continue to work without modification.

However the multi-tenant architecture offers less less capability for parallelism. Since every tenant is processed in at most one node (and several may share a node), few tenants means few utilized nodes. Additionally if some tenants are extraordinarily large compared with others then the nodes for the large tenants will experience higher load, even while some nodes may be under-utilized.

Real-time Analytics
-------------------

Many companies use a real-time dashboard to understand high volume events such as website clicks or sensor measurements. This requires quick aggregate query processing. With proper modeling this use case works well on Citus because balancing the data evenly across the nodes in a distributed database allows massively parallel processing for aggregate SQL queries.

Like the multi-tenant use case, real-time analytics on Citus can take advantage of dynamic scalability on commodity hardware to easily add or remove nodes. Unlike the the multi-tenant use case, it requires greater care to (re)write queries to minimize network overhead between nodes. 

To summarize, here are the tradeoffs of these two common use cases:

* Multi-Tenant
    * ✔ SQL Coverage
    * ✔ Ease of Migration
    * ✘ Less Parallelism
    * ✘ Less effective for large (or few) tenants
* Real-Time
    * ✔ Parallelism
    * ✔ Linear Scalability
    * ✘ Reduced SQL Coverage
    * ✘ Upfront Data Modeling

How to Distribute Data
----------------------

In every table you want to shard across multiple nodes you must designate exactly one column as the "distribution column." The value of this column for each row determines the shard where that row gets stored. The database maintains statistics about the distribution column in each shard and Citus’s distributed query optimizer then leverages these statistics to determine how best a query should be executed.

Typically, you should choose that column for distribution which is the most commonly used join key or on which most queries have filters. In filtered queries Citus uses the distribution column ranges to prune away unrelated shards, ensuring that the query hits only those shards which overlap with the WHERE clause ranges. For joins, if the join key is the same as the distribution column then Citus executes the join only between those shards which have matching or overlapping distribution column ranges. This helps greatly reduce both the amount of computation on each node and the network bandwidth involved in transferring shards across nodes. In addition to joins, choosing the right column as the distribution column also helps Citus push down several operations directly to the worker shards, hence reducing network I/O.

.. note::

  Citus also allows joining on non-distribution key columns by dynamically repartitioning the tables for the query. Still, joins on non-distribution keys require shuffling data across the cluster and therefore aren’t as efficient as joins on distribution keys.

In the multi-tenant situation situation all tables should be distributed by a tenant id, the meaning of which is specific to each application. For an example of identifying the tenant id, see :ref:`Multi-Tenant Migration`_. Real-time applications distribute by finer grained columns like user id. We refer to them more generally as entity ids.
