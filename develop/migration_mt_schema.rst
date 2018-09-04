.. _mt_schema_migration:

Identify Distribution Strategy
==============================

Pick distribution key
---------------------

The first step in migrating to Citus is to identify suitable distribution keys and plan table distribution accordingly. In multi-tenant applications this will typically be the internal identifier used to identify tenants. We typically refer to it as the "tenant ID." Use cases may vary, so we advise being thorough on this step.

We are happy to help review your environment to be sure that the ideal distribution key is chosen. To do so, we typically examine schema layouts, larger tables, long-running and/or problematic queries, standard use cases, and more.

Start by:

1. :ref:`app_type`
2. :ref:`distributed_data_modeling`

Identify types of tables
------------------------

Once a distribution key is identified, review the schema to identify how each table will be handled and whether any modifications to table layouts will be required. We typically advise tracking this with a spreadsheet, and have created a `template <https://examples.citusdata.com/citus-migration-plan.xlsx>`_ you can use.

Tables will generally fall into one of the following categories:

1. **Ready for distribution.** These tables already contain the distribution key, and are ready for distribution.
2. **Needs backfill.** These tables can be logically distributed by the chosen key, but do not contain a column directly referencing it. The tables will be modified later to add the column.
3. **Reference table.** These tables are typically small, do not contain the distribution key, are commonly joined by distributed tables, and/or are shared across tenants. A copy of each of these tables will be maintained on all nodes. Common examples include country code lookups, product categories, and the like.
4. **Local tables.** These tables are typically not joined to other tables, and do not contain the distribution key. They are maintained exclusively on the coordinator node. Common examples include admin user lookups and other utility tables.

Consider an example multi-tenant application similar to Etsy or Shopify where each tenant is a store. Here's a portion of a simplified schema:

.. figure:: ../images/erd/mt-before.png
   :alt: Schema before migration

   (Underlined items are primary keys, italicized items are foreign keys.)

In this example stores are a natural tenant. The tenant id is in this case the store_id. After distributing tables in the cluster, we want rows relating to the same store to reside together on the same nodes.

Prepare Tables for Migration
============================

Once the scope of needed database changes is identified, the next major step is to modify the data structure. First, existing tables requiring backfill are modified to add a column for the distribution key. 

Add distribution keys
---------------------

In our storefront example the stores and products tables have a store_id and are ready for distribution. Being normalized, the line_items table lacks a store id. If we want to distribute by store_id, the table needs this column.

.. code-block:: sql

  -- denormalize line_items by including store_id

  ALTER TABLE line_items ADD COLUMN store_id uuid;

Be sure to check that the distribution column has the same type in all tables, e.g. don't mix ``int`` and ``bigint``. The column types must match to ensure proper data colocation.

Include distribution column in keys
-----------------------------------

Citus :ref:`cannot enforce <non_distribution_uniqueness>` uniqueness constraints unless a unique index or primary key contains the distribution column. Thus we must modify primary and foreign keys in our example to include store_id.

Here are SQL commands to turn the simple keys composite:

.. code-block:: sql

  BEGIN;

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

Thus completed, our schema will look like this:

.. figure:: ../images/erd/mt-after.png
   :alt: Schema after migration

   (Underlined items are primary keys, italicized items are foreign keys.)

Be sure to modify data flows to add keys to incoming data.

Backfill newly created columns
------------------------------

Once the schema is updated, backfill missing values for the tenant_id column in tables where the column was added. In our example line_items requires values for store_id.

We join orders and line_items for the missing values:

.. code-block:: sql

  UPDATE line_items
     SET store_id = orders.store_id
    FROM line_items
   INNER JOIN orders
   WHERE line_items.order_id = orders.order_id;

Next, ensure incoming data sources are modified to add this data. Typically it involves some application-level changes and possibly changes in data import processes if relevant. This article has some useful information on modifying application-level SQL queries to have the distribution key needed for maximum benefit: 

Documentation request: a dedicated page for write-level application changes
