:orphan:

Installing Citus Enterprise Edition
===================================

.. _enterprise_debian:

Ubuntu or Debian with Internet Access
-------------------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Install Citus on all machines:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/deb.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # install the server and initialize db
    sudo apt-get install -y postgresql-12-citus-enterprise-9.5

    # preload citus extension
    sudo pg_conftool 12 main set shared_preload_libraries citus

3. Continue by following the standard :ref:`multi-machine debian <post_enterprise_deb>` installation steps, **starting at step 3.**

Ubuntu or Debian without Internet Access
----------------------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Create a package tarball:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/deb.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    sudo apt-get clean
    sudo apt-get install -y --download-only postgresql-12-citus-enterprise-9.5

    # go to package downloads
    cd /var/cache/apt

    # put them into a tarball
    tar czf ~/citus-enterprise.tar.gz *.deb

3. Copy the tarball onto machines that will be part of the Citus cluster.

4. Install the packages on all machines.

  .. code-block:: bash

    # on each machine:

    mkdir -p /tmp/citus
    tar zxf citus-enterprise.tar.gz -C /tmp/citus

    sudo dpkg -i -R /tmp/citus

    # preload citus extension
    sudo pg_conftool 12 main set shared_preload_libraries citus

5. Continue by following the standard :ref:`multi-machine debian <post_enterprise_deb>` installation steps, **starting at step 3.**

.. _enterprise_rhel:

Fedora, CentOS, or Red Hat with Internet Access
-----------------------------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Install Citus on all machines:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/rpm.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # install PostgreSQL with Citus extension
    sudo yum install -y citus-enterprise95_12

    # initialize system database (using RHEL 6 vs 7 method as necessary)
    sudo service postgresql-12 initdb || \
      sudo /usr/pgsql-12/bin/postgresql-12-setup initdb
    # preload citus extension
    echo "shared_preload_libraries = 'citus'" | \
      sudo tee -a /var/lib/pgsql/12/data/postgresql.conf

3. Continue by following the standard :ref:`multi-machine rhel <post_enterprise_rhel>` installation steps, **starting at step 3.**

Fedora, CentOS, or Red Hat without Internet Access
--------------------------------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Create a package tarball:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/rpm.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # get package
    sudo yum install --downloadonly --downloaddir=. citus-enterprise95_12

    # put them into a tarball
    tar czf ~/citus-enterprise.tar.gz *.rpm

3. Copy the tarball onto machines that will be part of the Citus cluster.

4. Install the packages on all machines.

  .. code-block:: bash

    # on each machine:

    mkdir -p /tmp/citus
    tar zxf citus-enterprise.tar.gz -C /tmp/citus

    sudo rpm -ivh /tmp/citus/*.rpm

    # initialize system database (using RHEL 6 vs 7 method as necessary)
    sudo service postgresql-12 initdb || \
      sudo /usr/pgsql-12/bin/postgresql-12-setup initdb
    # preload citus extension
    echo "shared_preload_libraries = 'citus'" | \
      sudo tee -a /var/lib/pgsql/12/data/postgresql.conf

5. Continue by following the standard :ref:`multi-machine rhel <post_enterprise_rhel>` installation steps, **starting at step 3.**

Upgrading from Citus Community to Enterprise
============================================

Ubuntu or Debian
----------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Determine your current Citus version with ``select * from citus_version();``.

3. Switch to Citus Enterprise packages for your current version. Do this on every node.

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/deb.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # Install enterprise packages, which will remove community packages
    sudo apt-get install -y postgresql-12-citus-enterprise-X.Y

    # substitute X.Y with the version currently installed ^^^^^

4. Restart the database.

  .. code-block:: bash

    sudo service postgresql restart

5. Update the Citus extension

   .. code-block:: bash

    sudo -i -u postgres psql -c "ALTER EXTENSION citus UPDATE;"

Fedora, CentOS, or Red Hat
--------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Determine your current Citus version with ``select * from citus_version();``.

3. Switch to Citus Enterprise packages for your current version. Do this on every node.

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/rpm.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # remove community packages
    # substitute XY with the version currently installed
    sudo yum remove -y citusXY_12

    # Install enterprise packages
    # substitute XY with the version previously installed
    sudo yum install -y citus-enterpriseXY_12

4. Restart the database.

  .. code-block:: bash

    sudo service postgresql-12 restart

5. Update the Citus extension

   .. code-block:: bash

    sudo -i -u postgres psql -c "ALTER EXTENSION citus UPDATE;"

Setting up High Availability
============================

The two steps in this section are optional for non-production clusters. The
goal is to use `pg_auto_failover <https://pg-auto-failover.readthedocs.io>`_ to
create secondary database nodes and fail over to them if primary nodes become
unhealthy.

.. _failover_pkg:

Install the pg_auto_failover enterprise package
-----------------------------------------------

Debian/Ubuntu
~~~~~~~~~~~~~

IMPORTANT: If upgrading from another Major or Minor pg_auto_failover version,
first stop the running pg_auto_failover service

.. code:: bash

    sudo apt-get update
    # Change to postgresql-11-auto-failover-enterprise-1.3 if you want to
    # install pg_auto_failover for PostgreSQL 11
    sudo apt-get install -y postgresql-12-auto-failover-enterprise-1.3

Redhat/CentOS
~~~~~~~~~~~~~

IMPORTANT: If upgrading from another Major or Minor Citus version, first stop
the running pg_auto_failover service and remove the old package

.. code:: bash

    # Change to pg-auto-failover-enterprise13_12 for PostgreSQL 11
    sudo yum install -y pg-auto-failover-enterprise13_12

.. _failover_setup:

Run the pg_auto_failover enterprise setup
-----------------------------------------

.. note::

  This is different from previous pg_auto_failover enterprise installation
  instructions.

Use ``pg-auto-failover-enterprise-pg-11-setup`` when installing for
Postgres 11.

.. code:: bash

    sudo pg-auto-failover-enterprise-pg-12-setup
    # Non-interactive version
    # IMPORTANT: you accept the license and encryption disclaimer here. The
    # encryption disclaimer is specific to pg_auto_failover, so be sure to read
    # and understand it even if you have read the one for Citus already.
    sudo PGAUTOFAILOVER_ACCEPT_LICENSE=YES \
         PGAUTOFAILOVER_ACCEPT_ENCRYPTION_DISCLAIMER=YES \
         PGAUTOFAILOVER_LICENSE_KEY=<INSERT LICENSE KEY HERE> \
         pg-auto-failover-enterprise-pg-12-setup
