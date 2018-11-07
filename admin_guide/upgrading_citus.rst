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

To upgrade a Citus version to its latest patch, issue a standard upgrade command for your package manager. Assuming version 8.0 is currently installed on Postgres 11:

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install --only-upgrade postgresql-11-citus-8.0
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  sudo yum update citus80_11
  sudo service postgresql-11.0 restart

.. _major_minor_upgrade:

Major and Minor Version Upgrades
--------------------------------

Major and minor version upgrades follow the same steps, but be careful: major upgrades can make backward-incompatible changes in the Citus API. It is best to review the Citus `changelog <https://github.com/citusdata/citus/blob/master/CHANGELOG.md>`_ before a major upgrade and look for any changes which may cause problems for your application.

Each major and minor version of Citus is published as a package with a separate name. Installing a newer package will automatically remove the older version. Here is how to upgrade from 7.5 to 8.0 for instance:

Step 1. Update Citus Package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install postgresql-10-citus-8.0
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  # Fedora, CentOS, or Red Hat
  sudo yum swap citus75_10 citus80_10
  sudo service postgresql-10 restart

Step 2. Apply Update in DB
~~~~~~~~~~~~~~~~~~~~~~~~~~

After installing the new package and restarting the database, run the extension upgrade script.

.. code-block:: bash

  # you must restart PostgreSQL before running this
  psql -c 'ALTER EXTENSION citus UPDATE;'

  # you should see the newer Citus version in the list
  psql -c '\dx'


.. note::

  During a major version upgrade, from the moment of yum installing a new
  version, Citus will refuse to run distributed queries until the server is restarted and
  ALTER EXTENSION is executed. This is to protect your data, as Citus object and
  function definitions are specific to a version. After a yum install you
  should (a) restart and (b) run alter extension. In rare cases if you
  experience an error with upgrades, you can disable this check via the
  :ref:`citus.enable_version_checks <enable_version_checks>` configuration
  parameter. You can also `contact us <https://www.citusdata.com/about/contact_us>`_
  providing information about the error, so we can help debug the issue.

.. _upgrading_postgres:

Upgrading PostgreSQL version from 10 to 11
##########################################

.. note::

   Do not attempt to upgrade *both* Citus and Postgres versions at once. If both upgrades are desired, upgrade Citus first. Older versions of Citus are not always compatible with the newest Postgres.

Record the following paths before you start (your actual paths may be different than those below):

Existing data directory (e.g. /opt/pgsql/10/data)
  :code:`export OLD_PG_DATA=/opt/pgsql/10/data`

Existing PostgreSQL installation path (e.g. /usr/pgsql-10)
  :code:`export OLD_PG_PATH=/usr/pgsql-10`

New data directory after upgrade
  :code:`export NEW_PG_DATA=/opt/pgsql/11/data`

New PostgreSQL installation path
  :code:`export NEW_PG_PATH=/usr/pgsql-11`

On Every Node (Coordinator and workers)
---------------------------------------

1. Back up Citus metadata in the old server.

  .. code-block:: postgres

    CREATE TABLE        public.pg_dist_partition AS
      SELECT * FROM pg_catalog.pg_dist_partition;
    CREATE TABLE        public.pg_dist_shard AS
      SELECT * FROM pg_catalog.pg_dist_shard;
    CREATE TABLE        public.pg_dist_placement AS
      SELECT * FROM pg_catalog.pg_dist_placement;
    CREATE TABLE        public.pg_dist_node_metadata AS
      SELECT * FROM pg_catalog.pg_dist_node_metadata;
    CREATE TABLE        public.pg_dist_node AS
      SELECT * FROM pg_catalog.pg_dist_node;
    CREATE TABLE        public.pg_dist_local_group AS
      SELECT * FROM pg_catalog.pg_dist_local_group;
    CREATE TABLE        public.pg_dist_transaction AS
      SELECT * FROM pg_catalog.pg_dist_transaction;
    CREATE TABLE        public.pg_dist_colocation AS
      SELECT * FROM pg_catalog.pg_dist_colocation;

2. Configure the new database instance to use Citus.

  * Include Citus as a shared preload library in postgresql.conf:

    .. code-block:: ini

      shared_preload_libraries = 'citus'

  * **DO NOT CREATE** Citus extension yet

  * **DO NOT** start the new server

3. Stop the old server.

4. Check upgrade compatibility.

   .. code-block:: bash

     $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                 -d $OLD_PG_DATA -D $NEW_PG_DATA --check

   You should see a "Clusters are compatible" message. If you do not, fix any errors before proceeding. Please ensure that

  * :code:`NEW_PG_DATA` contains an empty database initialized by new PostgreSQL version
  * The Citus extension **IS NOT** created

5. Perform the upgrade (like before but without the :code:`--check` option).

  .. code-block:: bash

    $NEW_PG_PATH/bin/pg_upgrade -b $OLD_PG_PATH/bin/ -B $NEW_PG_PATH/bin/ \
                                -d $OLD_PG_DATA -D $NEW_PG_DATA

6. Start the new server.

  * **DO NOT** run any query before running the queries given in the next step

7. Restore metadata.

  .. code-block:: postgres

    INSERT INTO pg_catalog.pg_dist_partition
      SELECT * FROM public.pg_dist_partition;
    INSERT INTO pg_catalog.pg_dist_shard
      SELECT * FROM public.pg_dist_shard;
    INSERT INTO pg_catalog.pg_dist_placement
      SELECT * FROM public.pg_dist_placement;
    INSERT INTO pg_catalog.pg_dist_node_metadata
      SELECT * FROM public.pg_dist_node_metadata;
    INSERT INTO pg_catalog.pg_dist_node
      SELECT * FROM public.pg_dist_node;
    TRUNCATE TABLE pg_catalog.pg_dist_local_group;
    INSERT INTO pg_catalog.pg_dist_local_group
      SELECT * FROM public.pg_dist_local_group;
    INSERT INTO pg_catalog.pg_dist_transaction
      SELECT * FROM public.pg_dist_transaction;
    INSERT INTO pg_catalog.pg_dist_colocation
      SELECT * FROM public.pg_dist_colocation;

8. Drop temporary metadata tables.

  .. code-block:: postgres

    DROP TABLE public.pg_dist_partition;
    DROP TABLE public.pg_dist_shard;
    DROP TABLE public.pg_dist_placement;
    DROP TABLE public.pg_dist_node_metadata;
    DROP TABLE public.pg_dist_node;
    DROP TABLE public.pg_dist_local_group;
    DROP TABLE public.pg_dist_transaction;
    DROP TABLE public.pg_dist_colocation;

9. Restart sequences.

  .. code-block:: postgres

    SELECT setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid)+1 AS max_shard_id FROM pg_dist_shard), false);

    SELECT setval('pg_catalog.pg_dist_placement_placementid_seq', (SELECT MAX(placementid)+1 AS max_placement_id FROM pg_dist_placement), false);

    SELECT setval('pg_catalog.pg_dist_groupid_seq', (SELECT MAX(groupid)+1 AS max_group_id FROM pg_dist_node), false);

    SELECT setval('pg_catalog.pg_dist_node_nodeid_seq', (SELECT MAX(nodeid)+1 AS max_node_id FROM pg_dist_node), false);

    SELECT setval('pg_catalog.pg_dist_colocationid_seq', (SELECT MAX(colocationid)+1 AS max_colocation_id FROM pg_dist_colocation), false);

10. Register triggers.

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

11. Set dependencies.

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
