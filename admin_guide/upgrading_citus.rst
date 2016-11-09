.. _upgrading:

Upgrading Citus
$$$$$$$$$$$$$$$

.. _upgrading_citus:

Upgrading Citus Versions
########################
Upgrading the Citus version requires first obtaining the new Citus extension and
then installing it in each of your database instances. The first step varies by
operating system.

.. _upgrading_citus_package:

Step 1. Update Citus Package
----------------------------

**OS X**

::

  brew update
  brew upgrade citus

**Ubuntu or Debian**

::

  sudo apt-get update
  sudo apt-get upgrade postgresql-9.5-citus

**Fedora, CentOS, or Red Hat**

::

  sudo yum update citus_95

.. _upgrading_citus_extension:

Step 2. Apply Update in DB
--------------------------

Restart PostgreSQL:

::

  pg_ctl -D /data/base -l logfile restart

::

  # after restarting postgres
  psql -c "ALTER EXTENSION citus UPDATE;"

  psql -c "\dx"
  # you should see a newer Citus 6.0 version in the list

That's all it takes! No further steps are necessary after updating
the extension on all database instances in your cluster.



.. _upgrading_postgres:

Upgrading PostgreSQL version from 9.5 to 9.6
############################################

Citus v6.0 is compatible with PostgreSQL 9.5.x and 9.6.x. If you are running
Citus on PostgreSQL versions 9.5 and wish to upgrade to version 9.6, Please
`contact us <https://www.citusdata.com/about/contact_us>`_ for upgrade steps.

.. note::
  PostgreSQL 9.6 requires using Citus 6.0.
