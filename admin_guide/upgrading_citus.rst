.. _upgrading:

Upgrading Citus
$$$$$$$$$$$$$$$

.. _upgrading_citus:

Upgrading Citus Versions
########################

Upgrading the Citus version requires first obtaining the new Citus extension and then installing it in each of your database instances. Citus uses separate packages for each minor version to ensure that running a default package upgrade will provide bug fixes but never break anything. Let's start by examining patch upgrades, the easiest kind.

Patch Version Upgrade
---------------------

To upgrade a Citus version to its latest patch, issue a standard upgrade command for your package manager. Assuming version 11.0 is currently installed on Postgres 14:

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install --only-upgrade postgresql-14-citus-beta-11.0
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  sudo yum update citus110_beta_14
  sudo service postgresql-14 restart

.. _major_minor_upgrade:

Major and Minor Version Upgrades
--------------------------------

Major and minor version upgrades follow the same steps, but be careful: they can make backward-incompatible changes in the Citus API. It is best to review the Citus `changelog <https://github.com/citusdata/citus/blob/master/CHANGELOG.md>`_ before an upgrade and look for any changes which may cause problems for your application.

.. note::

   Starting at version 8.1, new Citus nodes expect and require encrypted inter-node communication by default, whereas nodes upgraded to 8.1 from an earlier version preserve their earlier SSL settings. Be careful when adding a new Citus 8.1 (or newer) node to an upgraded cluster that does not yet use SSL. The :ref:`adding a worker <adding_worker_node>` section covers that situation.

Each major and minor version of Citus is published as a package with a separate name. Installing a newer package will automatically remove the older version.

Step 1. Update Citus Package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If upgrading both Citus and Postgres, always be sure to upgrade the Citus extension first, and the PostgreSQL version second (see :ref:`upgrading_postgres`). Here is how to do a Citus upgrade from 10.2 to 11.0 on Postgres 13:

**Ubuntu or Debian**

.. code-block:: bash

  sudo apt-get update
  sudo apt-get install postgresql-13-citus-beta-11.0
  sudo service postgresql restart

**Fedora, CentOS, or Red Hat**

.. code-block:: bash

  # Fedora, CentOS, or Red Hat
  sudo yum swap citus102_13 citus110_beta_13
  sudo service postgresql-13 restart

Step 2. Apply Update in DB
~~~~~~~~~~~~~~~~~~~~~~~~~~

After installing the new package and restarting the database, run the extension upgrade script.

.. code-block:: bash

  # you must restart PostgreSQL before running this
  psql -c 'ALTER EXTENSION citus UPDATE;'

  # you should see the newer Citus version in the list
  psql -c '\dx'

.. note::

  If upgrading to Citus 11.x from an earlier major version, run this
  extra command:

  .. code-block:: bash

    -- only on the coordinator node
    SELECT citus_finalize_upgrade_to_citus11();

  The upgrade function will make sure that all worker nodes have the right
  schema and metadata. It may take several minutes to run, depending on how
  much metadata needs to be synced.

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

Upgrading PostgreSQL version from 13 to 14
##########################################

.. note::

   Do not attempt to upgrade *both* Citus and Postgres versions at once. If both upgrades are desired, upgrade Citus first.

   Also, if you're running Citus 10.0 or 10.1, don't upgrade your Postgres version. Upgrade to at least Citus 10.2 and
   then perform the Postgres upgrade.

Record the following paths before you start (your actual paths may be different than those below):

Existing data directory (e.g. /opt/pgsql/10/data)
  :code:`export OLD_PG_DATA=/opt/pgsql/13/data`

Existing PostgreSQL installation path (e.g. /usr/pgsql-10)
  :code:`export OLD_PG_PATH=/usr/pgsql-13`

New data directory after upgrade
  :code:`export NEW_PG_DATA=/opt/pgsql/14/data`

New PostgreSQL installation path
  :code:`export NEW_PG_PATH=/usr/pgsql-14`

For Every Node
--------------

1. Back up Citus metadata in the old coordinator node.

  .. code-block:: postgres

    -- run this on the coordinator and worker nodes

    SELECT citus_prepare_pg_upgrade();

2. Configure the new database instance to use Citus.

  * Include Citus as a shared preload library in postgresql.conf:

    .. code-block:: ini

      shared_preload_libraries = 'citus'

  * **DO NOT CREATE** Citus extension

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

7. Restore metadata on new coordinator node.

  .. code-block:: postgres

    -- run this on the coordinator and worker nodes

    SELECT citus_finish_pg_upgrade();
