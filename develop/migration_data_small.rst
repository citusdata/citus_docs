Databases under 200GB
=====================

For smaller environments that can tolerate a little downtime, use a simple pg_dump/pg_restore process. Here are the steps.

1. Save the database structure:

   .. code-block:: bash

      pg_dump \
         --format=plain \
         --no-owner \
         --schema-only \
         --file=schema.sql \
         --schema=target_schema \
         postgres://user:pass@host:5432/db

2. Connect to the Citus cluster using psql and create the schema:

   .. code-block:: psql

      \i schema.sql

3. Run your :ref:`create_distributed_table` and :ref:`create_reference_table` statements. If you get an error about foreign keys, it's generally due to the order of operations. Drop foreign keys before distributing tables and then re-add them.

4. Put the application into maintenance mode, and disable any other writes to the old database.

5. Save the data from the old database to disk with pg_dump:

   .. code-block:: bash

      pg_dump \
         --format=custom \
         --no-owner \
         --data-only \
         --file=data.dump \
         --schema=target_schema \
         postgres://user:pass@host:5432/db

6. Import into Citus using pg_restore:

   .. code-block:: bash

      # remember to use connection details for Citus,
      # not the source database
      pg_restore  \
         --host=host \
         --dbname=dbname \
         --username=username \
         data.dump

      # it'll prompt you for the connection password

7. Test application.
8. Launch!
