.. _transitioning_mt:

Migrating an existing single-node PostgreSQL database to Citus sometimes requires adjusting the schema and queries for optimal performance. Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

Migration tactics differ between the two main Citus use cases of multi-tenant applications and real-time analytics. The former is requires fewer data model changes so we'll begin there.

Multi-tenant Data Model
=======================

Citus is well suited to hosting B2B multi-tenant application data. In this model application tenants share a Citus cluster and a schema and Citus keeps each tenant's data private. Each tenant's table data is stored in its own shard determined by a configurable tenant id column. Citus pushes queries down to run directly on the relevant tenant shard in the cluster, spreading out the computation. Once queries are routed this way they can be executed without concern for the rest of the cluster. These queries can use the full features of SQL, including joins and transactions, without running into the inherent limitations of a distributed system.

This section will explore how to model for the multi-tenant scenario, including necessary adjustments to the schema and queries.

Schema Migration
----------------

Migrating from a standalone database instance to a sharded multi-tenant system requires identifying and modifying three types of tables which we may term *per-tenant*, *reference*, and *global*. The distinction hinges on whether the tables have (or reference) a column serving as tenant id. The concept of tenant id depends on the application and who exactly are considered its tenants.

Consider an example multi-tenant application similar to Etsy or Shopify where each tenant is a store. Here's portion of a simplified schema:

.. code::

  admins
    email
    password

  stores
    id
    owner_email
    owner_password
    name
    url

  products
    id
    store_id
    name
    description
    category

  purchases
    id
    store_id
    product_id
    customer_id
    region_id
    price
    purchased_at

  regions
    id
    sales_tax

We'll classify the types of tables and learn how to migrate them to Citus.

Tenant-Specific Tables
^^^^^^^^^^^^^^^^^^^^^^

In our example each store is a natural tenant. This is because storefronts benefit from dedicated processing power for their customer data, and stores should not be able to access each other's sales or inventory. The tenant id is in this case the store id. Notice that some tables already have a store id as primary or foreign key. Tables such as these which can join on the tenant id are called *tenant-specific* or *per-tenant* tables. In this example they are stores, products and purchases.

Global and Reference Tables
^^^^^^^^^^^^^^^^^^^^^^^^^^^

The tenant-specific tables do not require modification for use in Citus. During migration you would distribute them through the Citus cluster, sharding by tenant id. The other tables — admins and regions — do require modification.

Consider the admins table first. It is aloof from tenant data, containing information about site administrators for the entire marketplace website, not individual stores. This table will not be involved in any SQL joins with the per-tenant tables. We call tables like these *global*. They usually relate to cross-tenant site operation or analytics. You can leave these tables unchanged, they will live on the Citus cluster master node and do not need to be distributed to worker nodes.

The regions table is a different story. Because it lacks a tenant id but is involved in calculations of sales pricing along with per-tenant tables we call it a *reference* table.

There are two ways to handle reference tables in the Citus multi-tenant use case:

1. Duplicate
2. Denormalize

The first way is to add and a store_id column to regions, change the primary key from id alone to a composite key of id and store_id, and shard by the store_id column. (Citus requires primary keys and uniqueness constraints to contain the distribution column.)

In addition to the schema change, you'll need to duplicate each row of the regions table, once for each store. To use the altered regions table in a join query, add a clause to match on store_id, for instance:

.. code-block:: sql

    -- Find adjusted purchase price with sales tax
    -- for purchase number 1337

    SELECT price + sales_tax
      FROM purchases, regions
     WHERE purchases.id = 1337
       AND purchases.region_id = regions.id
       -- include this condition:
       AND purchases.store_id = regions.store_id

This will run an efficient co-located join on the worker holding the shard for this store id.

The second technique is to remove the regions table and denormalizing the database by embedding the sales_tax property directly into purchases. Duplicating just one property isn't too bad, but the situation isn't as nice for wider reference tables. Note that reference columns can also be stored in a single JSONB column in the denormalized table to prevent the latter from becoming awkwardly wide.

Query Migration
---------------

To execute queries efficiently and isolate them within their tenant Citus needs to route them to a specific shard. Thus every query must identify which single tenant it involves. For non-joins this means that the *where* clause must filter by tenant id. In joins at least one of the tables must be filtered by tenant id. For instance:

.. code-block:: sql

  SELECT * FROM t1, t2
   WHERE t2.t1_id = t1.id
     AND t1.tenant_id = 43

An over-defensive but effective technique is to add the tenant id filter to any table name mentioned in a join. This is also important in CTEs. Due to a shortcoming in PostgreSQL the query planner cannot examine sibling queries in a CTE. To assist Citus in routing the SQL you need provide a hint.

.. code-block:: sql

  WITH cte1 AS ( Q ),
       cte2 AS (
         SELECT * FROM cte1, t3
          WHERE cte1.t3_id = t3.id
            AND t3.tenant_id = 42
       )
  SELECT * FROM cte2;
  -- need to filter by cte2.tenant_id out here too

Citus cannot see the filter on tenant_id inside cte2, so you need to add a redundant filter on the outermost query.

Real-Time Analytics Data Model
==============================

In this model multiple worker nodes calculate aggregate data in parallel for applications such as analytic dashboards. This scenario requires greater interaction between Citus nodes than the multi-tenant case and the migration from a standalone database is less straightforward.

In general you can distribute the tables from an existing schema by following the advice in :ref:`performance_tuning`. This will provide a baseline from which you can measure and interatively improve performance. For more migration guidance please `contact us <https://www.citusdata.com/about/contact_us>`_.
