.. _transitioning_mt:

Migrating an existing single-node PostgreSQL database to Citus sometimes requires adjusting the schema and queries for optimal performance. Citus extends PostgreSQL with distributed functionality, but it is not a drop-in replacement that scales out all workloads. A performant Citus cluster involves thinking about the data model, tooling, and choice of SQL features used.

Migration tactics differ between the two main Citus use cases of multi-tenant applications and real-time analytics. The former requires fewer data model changes so we'll begin there.

Multi-tenant Data Model
=======================

Citus is well suited to hosting B2B multi-tenant application data. In this model application tenants share a Citus cluster and a schema. Each tenant's table data is stored in a shard determined by a configurable tenant id column. Citus pushes queries down to run directly on the relevant tenant shard in the cluster, spreading out the computation. Once queries are routed this way they can be executed without concern for the rest of the cluster. These queries can use the full features of SQL, including joins and transactions, without running into the inherent limitations of a distributed system.

This section will explore how to model for the multi-tenant scenario, including necessary adjustments to the schema and queries.

Schema Migration
----------------

Migrating from a standalone database instance to a sharded multi-tenant system requires identifying and modifying three types of tables which we may term *per-tenant*, *reference*, and *global*. The distinction hinges on whether the tables have (or reference) a column serving as tenant id. The concept of tenant id depends on the application and who exactly are considered its tenants.

Consider an example multi-tenant application similar to Etsy or Shopify where each tenant is a store. Here's portion of a simplified schema:

.. image:: ../images/erd/mt-before.png

In our example each store is a natural tenant. This is because storefronts benefit from dedicated processing power for their customer data, and stores do not need to access each other's sales or inventory. The tenant id is in this case the store id. We want to distribute data in the cluster in such a way that rows from the above tables in our schema reside on the same node whenever the rows share a store id.

The first challenge is distributing the tables. Citus requires that primary keys contain the distribution column, so we must modify the primary keys of these tables and make them compound including a store id. The products table is already in perfect shape. Stores and orders need modification but that's easy. The main hurdle is updating line_items which, being normalized, lacks a store id. We must add that column, and include it in the primary key constraint.

When the job is complete our schema will look like this:

.. image:: ../images/erd/mt-after.png

We call the tables considered so far *per-tenant* because queries for our use case request information about them one tenant at a time. Their rows are distributed across the cluster according to the hashed values of their tenant ids.

There are other types of tables to consider during a transition to Citus. Some are system-wide tables such as information about site administrators. They do not participate in join queries with the per-tenant tables and may remain on the coordinator node with no modification.

Another kind of table are those which join with per-tenant tables but which aren't naturally specific to any one tenant. We call them *reference* tables. One example is shipping regions. We advise that you add a tenant id to these tables and duplicate the original rows, once for each tenant. This ensures that reference data is co-located with per-tenant data and quickly accessible to queries.

Data Migration
--------------

In the previous section we ensured that per-tenant tables have the tenant id, and that this column is part of the primary key. In tables such as line_items this caused denormalization. Once you're ready to copy data into a Citus cluster from the original line_items table we will need to "backfill" the store ids into new rows.

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
