.. _distributed_data_modeling:

Distributed modeling refers to choosing how to distribute information across nodes in a multi-machine database cluster and query it efficiently. There are common use cases for a distributed database with well understood design tradeoffs. It will be helpful for you to identify whether your application falls into one of these categories in order to know what features and performance to expect.

Citus uses a column in each table to determine how to allocate its rows among the available shards. In particular, as data is loaded into the table, Citus uses this so-called *distribution column* as a hash key to allocate each incoming row to a shard.

The database administrator, not Citus, picks the distribution column of each table. Thus the main task in distributed modeling is choosing the best division of tables and their distribution columns to fit the queries required by an application.

Determining the Data Model
==========================

As explained in :ref:`when_to_use_citus`, there are two main use cases for Citus. The first is the **multi-tenant architecture** (MT). This is common for the backend of a website that serves other companies, accounts, or organizations. An example of such a site is one which hosts store-fronts and does order processing for other businesses. Sites like these want to continue scaling as they get new tenants without encountering a hard tenant limit. Flexibly pooling the resources of servers in a distributed
database results in lower operational costs for this use-case than creating separate servers and database installations for each tenant.

There are characteristics of queries and schemas that suggest the multi-tenant architecture. Typical MT queries relate to a single tenant rather than joining information across tenants. This includes the OLTP workload for serving a web clients, and single-tenant OLAP for the site administrator. Having many tables in a database schema is another MT indicator.

The second use case is **real-time analytics**. In this case the database must ingest a large amount of incoming data and summarize it in real-time. Examples include making dashboards for data from the internet of things, or from web traffic. In this use case applications want massive parallelism, coordinating hundreds of cores for fast results to numerical, statistical, or counting queries.

The real-time architecture usually has few tables, often centering around a big table of device-, site- or user-events. It deals with high volume reads and writes, with relatively simple but computationally intensive lookups. Conversely a schema with many tables or using a rich set of SQL commands is less suited for the real-time architecture.

If your situation resembles either of these cases then the next step is to decide how to shard your data in a Citus cluster. As explained in :ref:`introduction_to_citus`, Citus assigns table rows to shards according to the hashed value of the table's distribution column. The database administrator's choice of distribution columns needs to match the access patterns of typical queries to ensure performance.

Distributing by Tenant ID
=========================

The multi-tenant architecture uses a form of hierarchical database modeling to partition query computations across machines in the distributed cluster. The top of the data hierarchy is known as the *tenant id*, and needs to be stored in a column on each table. Citus inspects queres to see which tenant id they involve and routes the query to a single physical node for processing, specifically the node which holds the data shard associated with the tenant id. Running a query with all relevant data placed on the same node is called *co-location*.

The first step is identifying what constitutes a tenant in your app. Common instances include company, account, organization, or customer. The column name will thus be something like :code:`company_id` or :code:`customer_id:`. Examine each of your queries and ask yourself: would it work if it had additional WHERE clauses to restrict all tables involved to rows with the same tenant id? You can visualize these clauses as executing queries *within* a context, such restricting queries on sales or inventory to be within a certain store.

If you're migrating an existing database to the Citus multi-tenant architecture then some of your tables may lack a column for the application-specific tenant id. You will need to add one and fill it with the correct values. This will denormalize your tables slightly, but it's because the multi-tenant model mixes the characteristics of hierarchical and relational data models. For more details and a concrete example of backfilling the tenant id, see our guide to :ref:`transitioning_to_citus`_.

Distributing by Entity ID
=========================

  "All multi-tenant databases are alike; each real-time database is sharded in its own way."

While the multi-tenant architecture introduces a hierarchical structure and uses data co-location to parallelize queries between tenants, real-time architectures depend on specific distribution properties of their data to achieve highly parallel processing.

Real-time queries typically ask for numeric aggregates grouped by date or category. Citus sends these queries to each shard for partial results and assembles the final answer on the coordinator node. Hence queries run fastest when as many nodes contribute as possible, and when no individual node bottlenecks.

Thus it is important to choose a column that distributes data evenly across shards. At the least this column should have a high cardinality. For instance a binary gender field is a poor choice because it assumes at most two values. These values will not be able to take advantage of a cluster with many shards. The row placement will skew into only two shards:

.. image:: ../images/sharding-poorly-distributed.png

Of columns having high cardinality, it is good additionally to choose those that are frequently used in group-by clauses or as join keys. Distributing by join keys co-locates the joined tables and greatly improves join speed. However schemas with many tables and a variety of joins are typically not well suited to the real-time architecture. Real-time schemas usually have a smaller number of tables, and are generally centered around a big table of quantitative events.

Let's examine typical real-time schemas.

Raw Events Table
----------------

Events and Summaries
--------------------

Updatable Large Table
---------------------

Behavioral Analytics
--------------------

Star Schema
-----------

Modeling Concepts
=================


