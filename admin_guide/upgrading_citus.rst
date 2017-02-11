.. _upgrading:

Upgrading Citus
$$$$$$$$$$$$$$$

.. _upgrading_citus:

Upgrading Citus Versions
########################

Citus adheres to `semantic versioning <http://semver.org/>`_ with patch-, minor-, and major-versions. The upgrade process differs for each, requiring more effort for bigger version jumps.

Upgrading the Citus version requires first obtaining the new Citus extension and then installing it in each of your database instances. Citus uses separate packages for each minor version to ensure that running a default package upgrade will provide bug fixes but never break anything. Let's start by examining patch upgrades, the easiest kind.

Patch Version Upgrade
---------------------

To upgrade a Citus version to its latest patch, issue a standard upgrade command for your package manager. Assuming version 6.1 is currently installed:

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install --only-upgrade postgresql-9.6-citus-6.1
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  sudo yum update citus61_96
  sudo service postgresql-9.6 restart

.. _major_minor_upgrade:

Major and Minor Version Upgrades
--------------------------------

Major and minor version upgrades follow the same steps, but be careful: major upgrades can make backward-incompatible changes in the Citus API. It is best to review the Citus `changelog <https://github.com/citusdata/citus/blob/master/CHANGELOG.md>`_ before a major upgrade and look for any changes which may cause problems for your application.

Each major and minor version of Citus is published as a package with a separate name. Installing a newer package will automatically remove the older version. Here is how to upgrade from 6.0 to 6.1 for instance:

Step 1. Update Citus Package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install postgresql-9.6-citus-6.1
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  # Fedora, CentOS, or Red Hat
  sudo yum swap citus60_96 citus61_96
  sudo service postgresql-9.6 restart

Step 2. Apply Update in DB
~~~~~~~~~~~~~~~~~~~~~~~~~~

After installing the new package, run the extension upgrade script:

.. code-block:: bash

  psql -c 'ALTER EXTENSION citus UPDATE;'

  psql -c '\dx'
  # you should see the newer Citus version in the list

.. _upgrading_postgres:

Upgrading PostgreSQL version from 9.5 to 9.6
############################################

.. note::
  PostgreSQL 9.6 requires using Citus 6.0 or greater. To upgrade PostgreSQL with an older version of Citus, first upgrade Citus as explained in :ref:`major_minor_upgrade`.

Record the following paths before you start (your actual paths may be different than those below):

Existing data directory (e.g. /opt/pgsql/9.5/data)
  :code:`export OLD_PG_DATA=/opt/pgsql/9.5/data`

Existing PostgreSQL installation path (e.g. /usr/pgsql-9.5)
  :code:`export OLD_PG_PATH=/usr/pgsql-9.5`

New data directory after upgrade
  :code:`export NEW_PG_DATA=/opt/pgsql/9.6/data`

New PostgreSQL installation path
  :code:`export NEW_PG_PATH=/usr/pgsql-9.6`

On the Coordinator Node
-----------------------

1. If using Citus v5.x follow the :ref:`previous steps <major_minor_upgrade>` to install Citus 6.0 onto the existing postgresql 9.5 server.
2. Back up Citus metadata in the old server.

  .. code-block:: postgres

    CREATE TABLE public.pg_dist_partition AS SELECT * FROM pg_catalog.pg_dist_partition;
    CREATE TABLE public.pg_dist_shard AS SELECT * FROM pg_catalog.pg_dist_shard;
    CREATE TABLE public.pg_dist_shard_placement AS SELECT * FROM pg_catalog.pg_dist_shard_placement;
    CREATE TABLE public.pg_dist_node AS SELECT * FROM pg_catalog.pg_dist_node;
    CREATE TABLE public.pg_dist_local_group AS SELECT * FROM pg_catalog.pg_dist_local_group;
    CREATE TABLE public.pg_dist_transaction AS SELECT * FROM pg_catalog.pg_dist_transaction;
    CREATE TABLE public.pg_dist_colocation AS SELECT * FROM pg_catalog.pg_dist_colocation;

3. Configure the new database instance to use Citus.
  * Include Citus as a shared preload library in postgresql.conf:
  .. code-block:: ini

    shared_preload_libraries = 'citus'

  * **DO NOT CREATE** Citus extension yet

4. Stop the old and new servers.

5. Check upgrade compatibility.

  .. code-block:: bash

    $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                -d $OLD_PG_DATA -D $NEW_PG_DATA --check

  You should see a "Clusters are compatible" message. If you do not, fix any errors before proceeding. Please ensure that

  * :code:`NEW_PG_DATA` contains an empty database initialized by new PostgreSQL version
  * The Citus extension **IS NOT** created

6. Perform the upgrade (like before but without the :code:`--check` option).

  .. code-block:: bash

    $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                -d $OLD_PG_DATA -D $NEW_PG_DATA

7. Start the new server.

8. Restore metadata.

  .. code-block:: postgres

    INSERT INTO pg_catalog.pg_dist_partition SELECT * FROM public.pg_dist_partition;
    INSERT INTO pg_catalog.pg_dist_shard SELECT * FROM public.pg_dist_shard;
    INSERT INTO pg_catalog.pg_dist_shard_placement SELECT * FROM public.pg_dist_shard_placement;
    INSERT INTO pg_catalog.pg_dist_node SELECT * FROM public.pg_dist_node;
    TRUNCATE TABLE pg_catalog.pg_dist_local_group;
    INSERT INTO pg_catalog.pg_dist_local_group SELECT * FROM public.pg_dist_local_group;
    INSERT INTO pg_catalog.pg_dist_transaction SELECT * FROM public.pg_dist_transaction;
    INSERT INTO pg_catalog.pg_dist_colocation SELECT * FROM public.pg_dist_colocation;

9. Drop temporary metadata tables.

  .. code-block:: postgres

    DROP TABLE public.pg_dist_partition;
    DROP TABLE public.pg_dist_shard;
    DROP TABLE public.pg_dist_shard_placement;
    DROP TABLE public.pg_dist_node;
    DROP TABLE public.pg_dist_local_group;
    DROP TABLE public.pg_dist_transaction;
    DROP TABLE public.pg_dist_colocation;

10. Restart sequences.

  .. code-block:: postgres

    SELECT setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid)+1 AS max_shard_id FROM pg_dist_shard), false);

    SELECT setval('pg_catalog.pg_dist_groupid_seq', (SELECT MAX(groupid)+1 AS max_group_id FROM pg_dist_node), false);

    SELECT setval('pg_catalog.pg_dist_node_nodeid_seq', (SELECT MAX(nodeid)+1 AS max_node_id FROM pg_dist_node), false);

    SELECT setval('pg_catalog.pg_dist_shard_placement_placementid_seq', (SELECT MAX(placementid)+1 AS max_placement_id FROM pg_dist_shard_placement), false);

    SELECT setval('pg_catalog.pg_dist_colocationid_seq', (SELECT MAX(colocationid)+1 AS max_colocation_id FROM pg_dist_colocation), false);

11. Register triggers.

  .. code-block:: postgres

    CREATE OR REPLACE FUNCTION create_truncate_trigger(table_name regclass) RETURNS void LANGUAGE plpgsql as $$
    DECLARE
      command  text;
      trigger_name text;

    BEGIN
      trigger_name := 'truncate_trigger_' || table_name::oid;
      command := 'create trigger ' || trigger_name || ' after truncate on ' || table_name || ' execute procedure pg_catalog.citus_truncate_trigger()';
      execute command;
      command := 'update pg_trigger set tgisinternal = true where tgname
     = ' || quote_literal(trigger_name);
      execute command;
    END;
    $$;

    SELECT create_truncate_trigger(logicalrelid) FROM pg_dist_partition ;

    DROP FUNCTION create_truncate_trigger(regclass);

12. Set dependencies.

  .. code-block:: postgres

    INSERT INTO
      pg_depend
    SELECT
      'pg_class'::regclass::oid as classid,
      p.logicalrelid::regclass::oid as objid,
      0 as objsubid,
      'pg_extension'::regclass::oid as refclassid,
      (select oid from pg_extension where extname = 'citus') as refobjid,
      0 as refobjsubid ,
      'n' as deptype
    FROM
      pg_dist_partition p;

On Worker Nodes
---------------

1. Install Citus 6.0 onto existing PostgreSQL 9.5 server as outlined in :ref:`major_minor_upgrade`.
2. Stop the old and new servers.
3. Check upgrade compatibility to PostgreSQL 9.6.

  .. code-block:: bash

    $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                -d $OLD_PG_DATA -D $NEW_PG_DATA --check

  You should see a "Clusters are compatible" message. If you do not, fix any errors before proceeding. Please ensure that

  * :code:`NEW_PG_DATA` contains an empty database initialized by new PostgreSQL version
  * The Citus extension **IS NOT** created

4. Perform the upgrade (like before but without the :code:`--check` option).

  .. code-block:: bash

    $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                -d $OLD_PG_DATA -D $NEW_PG_DATA

5. Start the new server.
