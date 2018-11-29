.. _mt_schema_migration:

Identify Distribution Strategy
==============================

Pick distribution key
---------------------

The first step in migrating to Citus is identifying suitable distribution keys and planning table distribution accordingly. In multi-tenant applications this will typically be an internal identifier for tenants. We typically refer to it as the "tenant ID." The use-cases may vary, so we advise being thorough on this step.

For guidance, read these sections:

1. :ref:`app_type`
2. :ref:`distributed_data_modeling`

We are happy to help review your environment to be sure that the ideal distribution key is chosen. To do so, we typically examine schema layouts, larger tables, long-running and/or problematic queries, standard use cases, and more.

Identify types of tables
------------------------

Once a distribution key is identified, review the schema to identify how each table will be handled and whether any modifications to table layouts will be required. We typically advise tracking this with a spreadsheet, and have created a `template <https://docs.google.com/spreadsheets/d/1jYlc22lHdP91pTrb6s35QfrN9nTE1BkVJnCSZeQ7ZmI/edit>`_ you can use.

Tables will generally fall into one of the following categories:

1. **Ready for distribution.** These tables already contain the distribution key, and are ready for distribution.
2. **Needs backfill.** These tables can be logically distributed by the chosen key, but do not contain a column directly referencing it. The tables will be modified later to add the column.
3. **Reference table.** These tables are typically small, do not contain the distribution key, are commonly joined by distributed tables, and/or are shared across tenants. A copy of each of these tables will be maintained on all nodes. Common examples include country code lookups, product categories, and the like.
4. **Local table.** These are typically not joined to other tables, and do not contain the distribution key. They are maintained exclusively on the coordinator node. Common examples include admin user lookups and other utility tables.

Consider an example multi-tenant application similar to Etsy or Shopify where each tenant is a store. Here's a portion of a simplified schema:

.. figure:: ../images/erd/mt-before.png
   :alt: Schema before migration

   (Underlined items are primary keys, italicized items are foreign keys.)

In this example stores are a natural tenant. The tenant id is in this case the store_id. After distributing tables in the cluster, we want rows relating to the same store to reside together on the same nodes.

.. _prepare_source_tables:

Prepare Source Tables for Migration
===================================

Once the scope of needed database changes is identified, the next major step is to modify the data structure for the application's existing database. First, tables requiring backfill are modified to add a column for the distribution key.

Add distribution keys
---------------------

In our storefront example the stores and products tables have a store_id and are ready for distribution. Being normalized, the line_items table lacks a store id. If we want to distribute by store_id, the table needs this column.

.. code-block:: sql

  -- denormalize line_items by including store_id

  ALTER TABLE line_items ADD COLUMN store_id uuid;

Be sure to check that the distribution column has the same type in all tables, e.g. don't mix ``int`` and ``bigint``. The column types must match to ensure proper data colocation.

Backfill newly created columns
------------------------------

Once the schema is updated, backfill missing values for the tenant_id column in tables where the column was added. In our example line_items requires values for store_id.

We backfill the table by obtaining the missing values from a join query with orders:

.. code-block:: sql

  UPDATE line_items
     SET store_id = orders.store_id
    FROM line_items
   INNER JOIN orders
   WHERE line_items.order_id = orders.order_id;

Doing the whole table at once may cause too much load on the database and disrupt other queries. The backfill can done more slowly instead. One way to do that is to make a function that backfills small batches at a time, then call the function repeatedly with `pg_cron <https://github.com/citusdata/pg_cron>`_.

.. code-block:: postgresql

   -- the a function to backfill up to
   -- one thousand rows from line_items

   CREATE FUNCTION backfill_batch()
   RETURNS void LANGUAGE sql AS $$
     WITH batch AS (
       SELECT line_items_id, order_id
         FROM line_items
        WHERE store_id IS NULL
        LIMIT 1000
          FOR UPDATE
         SKIP LOCKED
     )
     UPDATE line_items AS li
        SET store_id = orders.store_id
       FROM batch, orders
      WHERE batch.line_item_id = li.line_item_id
        AND batch.order_id = orders.order_id;
   $$;

   -- run the function every half hour
   SELECT cron.schedule('*/30 * * * *', 'SELECT backfill_batch()');

   -- ^^ note the return value of cron.schedule

Once the backfill is caught up, the cron job can be disabled:

.. code-block:: postgresql

   -- assuming 42 is the job id returned
   -- from cron.schedule

   SELECT cron.unschedule(42);
