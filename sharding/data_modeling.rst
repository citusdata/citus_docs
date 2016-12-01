.. _distributed_data_modeling:

Distributed modeling refers to choosing how to distribute information across nodes in a multi-machine database cluster and query it efficiently. There are common use cases for a distributed database with well understood design tradeoffs. It will be helpful for you to identify whether your application falls into one of these categories in order to know what features and performance to expect.

Choosing Distribution Column
============================

Citus uses the distribution column of a table to determine how data is allocated to the available shards. As data is loaded into the table, the distribution key column is treated as a hash key to allocate the incoming row to a shard. Repeating values are always assigned the same shard. Therefore the distribution column can also be used by the system to find the shard containing a particular value or set of values.

The database administrator, not Citus, designates the distribution column of a table. It is important to choose a column that both distributes data evenly across shards and co-locates rows from multiple tables on the same distributed node when they are used together in queries. Thus for the first point it is best to choose a column with high cardinality. For instance a binary gender field is a poor choice because it assumes at most two values. For the second point, choosing a column on which two tables are typically joined also helps join queries operate more efficiently because table rows to be joined will be co-located in the same shards.

* [add a picture of evenly distributed data in shards vs uneven]
* [add a picture of co-location]

Citus has two predominant use cases, each with characteristic patterns of distribution columns. They are multi-tenant applications and real time analytic dashboards.

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
