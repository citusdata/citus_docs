.. _mt_schema_migration:

Identify Distribution Strategy
==============================

Pick distribution key that best addresses use case
--------------------------------------------------

Your first step when migrating to Citus should be to identify a suitable distribution key and plan table distribution accordingly. If your application is multi-tenant, this will typically be the internal identifier you use to identify tenants, so some linked documentation refers to this value as “tenant ID”. Certain use cases may vary, so we advise being thorough on this step. 

We are happy to help review your environment to be sure that the ideal distribution key is chosen. To do so, we typically examine schema layouts, larger tables, long-running and/or problematic queries, standard use cases, and more. 

The following pages go into further detail about data modeling strategies for common use cases:

https://docs.citusdata.com/en/latest/use_cases/multi_tenant.html 

https://docs.citusdata.com/en/latest/articles/sharding_mt_app.html 

Once a distribution key is identified, the schema is reviewed to identify how each table will be handled and any modifications to table layouts that will be required. We typically advise tracking this with a spreadsheet similar to the example found here: 

https://docs.google.com/spreadsheets/d/14Hsa8Yrsf5ytAcminT7RztlR_0Dn3K17PL0iLvYCR4c/edit#gid=692529705 

Tables will generally fall into one of the following categories: 

1. **Ready for distribution.** These tables already contain the distribution key, and are ready. 
2. **Needs backfill.** These tables can be logically distributed by the chosen key, but do not contain a column directly referencing it. These will be modified to add the value later
3. **Reference table.** These tables are typically small, do not contain the distribution key, are commonly joined by distributed tables, and/or are shared across tenants. A copy of each of these tables will be maintained on all nodes. Common examples include country code lookups, product categories, and the like. 
4. **Local tables.** These tables are typically not joined to other tables, and do not contain the distribution key. They are maintained exclusively on the coordinator node. Common examples include admin user lookups and other utility tables. 

Identify distributed, reference, and local tables
-------------------------------------------------

Transitioning from a standalone database instance to a sharded multi-tenant system requires identifying and modifying three types of tables which we may term *per-tenant*, *reference*, and *global*. The distinction hinges on whether the tables have (or reference) a column serving as tenant id. The concept of tenant id depends on the application and who exactly are considered its tenants.

Consider an example multi-tenant application similar to Etsy or Shopify where each tenant is a store. Here's a portion of a simplified schema:

.. figure:: ../images/erd/mt-before.png
   :alt: Schema before migration

   (Underlined items are primary keys, italicized items are foreign keys.)

In our example each store is a natural tenant. This is because storefronts benefit from dedicated processing power for their customer data, and stores do not need to access each other's sales or inventory. The tenant id is in this case the store id. We want to distribute data in the cluster in such a way that rows from the above tables in our schema reside on the same node whenever the rows share a store id.

The first step is preparing the tables for distribution. Citus requires that primary keys contain the distribution column, so we must modify the primary keys of these tables and make them compound including a store id. Making primary keys compound will require modifying the corresponding foreign keys as well.

In our example the stores and products tables are already in perfect shape. The orders table needs slight modification: updating the primary and foreign keys to include store_id. The line_items table needs the biggest change. Being normalized, it lacks a store id. We must add that column, and include it in the primary key constraint.

Here are SQL commands to accomplish these changes:

.. code-block:: sql

  BEGIN;

  -- denormalize line_items by including store_id

  ALTER TABLE line_items ADD COLUMN store_id uuid;

  -- drop simple primary keys (cascades to foreign keys)

  ALTER TABLE products   DROP CONSTRAINT products_pkey CASCADE;
  ALTER TABLE orders     DROP CONSTRAINT orders_pkey CASCADE;
  ALTER TABLE line_items DROP CONSTRAINT line_items_pkey CASCADE;

  -- recreate primary keys to include would-be distribution column

  ALTER TABLE products   ADD PRIMARY KEY (store_id, product_id);
  ALTER TABLE orders     ADD PRIMARY KEY (store_id, order_id);
  ALTER TABLE line_items ADD PRIMARY KEY (store_id, line_item_id);

  -- recreate foreign keys to include would-be distribution column

  ALTER TABLE line_items ADD CONSTRAINT line_items_store_fkey
    FOREIGN KEY (store_id) REFERENCES stores (store_id);
  ALTER TABLE line_items ADD CONSTRAINT line_items_product_fkey
    FOREIGN KEY (store_id, product_id) REFERENCES products (store_id, product_id);
  ALTER TABLE line_items ADD CONSTRAINT line_items_order_fkey
    FOREIGN KEY (store_id, order_id) REFERENCES orders (store_id, order_id);

  COMMIT;

When the job is complete our schema will look like this:

.. figure:: ../images/erd/mt-after.png
   :alt: Schema after migration

   (Underlined items are primary keys, italicized items are foreign keys.)

We call the tables considered so far *per-tenant* because querying them for our use case requires information for only one tenant per query. Their rows are distributed across the cluster according to the hashed values of their tenant ids.

There are other types of tables to consider during a transition to Citus. Some are system-wide tables such as information about site administrators. We call them *global* tables and they do not participate in join queries with the per-tenant tables and may remain on the Citus coordinator node unmodified.

Another kind of table are those which join with per-tenant tables but which aren't naturally specific to any one tenant. We call them *reference* tables. Two examples are shipping regions and product categories. We advise that you add a tenant id to these tables and duplicate the original rows, once for each tenant. This ensures that reference data is co-located with per-tenant data and quickly accessible to queries.

Prepare Tables for Migration
============================

Once the scope of needed database changes is identified, the next major step is to modify your data structure. First, existing tables requiring backfill (see category 2 above) are modified to add a column for the distribution key. Type normalization may also be required at this stage to keep key columns with the same value in different data types from becoming a problem. This page contains further information on this topic:

https://docs.citusdata.com/en/latest/develop/migration_mt_schema.html 

Next, incoming data sources are modified to add this data automatically. This typically involves some application-level changes and possibly changes in data import processes if relevant. This article has some useful information on modifying application-level SQL queries to have the distribution key needed for maximum benefit: 

Documentation request: a dedicated page for write-level application changes

The following articles go into detail about migrating to Citus on several popular platforms: 

Documentation request: below pages may need to differentiate between read- and write-level application changes

Rails apps can use our activerecord-multi-tenant Ruby gem as seen here: 
https://docs.citusdata.com/en/latest/develop/migration_mt_ror.html 
Django applications can use our django-multitenant Python library:  
https://docs.citusdata.com/en/latest/develop/migration_mt_django.html  
ASP.NET projects can benefit from the 3rd party SAASkit as seen here: 
https://docs.citusdata.com/en/latest/develop/migration_mt_asp.html 
Java Hibernate projects will benefit from this blog post:
https://www.citusdata.com/blog/2018/02/13/using-hibernate-and-spring-to-build-multitenant-java-apps/ 
Other applications can benefit from the advice here: 
	Documentation request: general app migration advice

Once that is complete, it is time to backfill the new column(s) for existing data to ensure forwards compatibility. This page has further information on this topic: 

Documentation request: how to use pg_cron to backfill in chunks

https://docs.citusdata.com/en/latest/develop/migration_mt_schema.html#backfilling-tenant-id 

Add distribution keys to tables as needed
-----------------------------------------

Modify data flows to add keys to incoming data
----------------------------------------------

Backfill newly created columns
------------------------------

Once the schema is updated and the per-tenant and reference tables are distributed across the cluster, it's time to copy data from the original database into Citus. Most per-tenant tables can be copied directly from source tables. However line_items was denormalized with the addition of the store_id column. We have to "backfill" the correct values into this column.

We join orders and line_items to output the data we need including the backfilled store_id column. The results can go into a file for later import into Citus.

.. code-block:: sql

  -- This query gets line item information along with matching store_id values.
  -- You can save the result to a file for later import into Citus.

  SELECT orders.store_id AS store_id, line_items.*
    FROM line_items, orders
   WHERE line_items.order_id = orders.order_id

To learn how to ingest datasets such as the one generated above into a Citus cluster, see :ref:`dml`.
