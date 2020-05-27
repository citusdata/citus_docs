:orphan:

Installing Citus Enterprise Edition, Microsoft SKU
==================================================

These instructions cover obtaining and installing the Microsoft SKU version of
Citus Enterprise edition. After the Microsoft-specific steps, it directs you to
our standard Citus :ref:`production` installation steps.

Here are the high level Microsoft SKU steps we'll be doing in this part of the
guide:

1. :ref:`sku_configure`
2. :ref:`sku_pgdg`
3. :ref:`sku_pkg`
4. :ref:`sku_setup`
5. :ref:`sku_use`
6. :ref:`sku_failover_pkg`
7. :ref:`sku_failover_setup`

.. _sku_configure:

Configure the Citus Enterprise Microsoft repositories
-----------------------------------------------------

.. note::

  This is different from previous Citus Enterprise installation instructions.

Ubuntu/Debian
~~~~~~~~~~~~~

First follow these shared steps and then run the OS version specific
command in one of the sections below.

.. code:: bash

    sudo apt-get install -y apt-transport-https curl gnupg
    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

Ubuntu 16.04 xenial
$$$$$$$$$$$$$$$$$$$

.. code:: bash

    echo "deb [arch=amd64] https://packages.microsoft.com/repos/citus-ubuntu xenial main" | sudo tee /etc/apt/sources.list.d/citus-enterprise-microsoft.list

Ubuntu 18.04 bionic
$$$$$$$$$$$$$$$$$$$

.. code:: bash

    echo "deb [arch=amd64] https://packages.microsoft.com/repos/citus-ubuntu bionic main" | sudo tee /etc/apt/sources.list.d/citus-enterprise-microsoft.list

Debian 8 Jessie
$$$$$$$$$$$$$$$

.. code:: bash

    echo "deb [arch=amd64] https://packages.microsoft.com/repos/citus-debian jessie main" | sudo tee /etc/apt/sources.list.d/citus-enterprise-microsoft.list

Debian 9 Stretch
$$$$$$$$$$$$$$$$

.. code:: bash

    echo "deb [arch=amd64] https://packages.microsoft.com/repos/citus-debian stretch main" | sudo tee /etc/apt/sources.list.d/citus-enterprise-microsoft.list

Debian 10 Buster
$$$$$$$$$$$$$$$$

.. code:: bash

    echo "deb [arch=amd64] https://packages.microsoft.com/repos/citus-debian buster main" | sudo tee /etc/apt/sources.list.d/citus-enterprise-microsoft.list

Redhat/CentOS
~~~~~~~~~~~~~

Redhat 6/CentOS 6
$$$$$$$$$$$$$$$$$

.. code:: bash

    sudo cat > /etc/yum.repos.d/citus-enterprise-microsoft.repo << EOF
    [packages-microsoft-com-citus-centos6]
    name=packages-microsoft-com-citus-centos6
    baseurl=https://packages.microsoft.com/yumrepos/citus-centos6/
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.microsoft.com/keys/microsoft.asc
    EOF

Redhat 7/CentOS 7
$$$$$$$$$$$$$$$$$

.. code:: bash

    sudo cat > /etc/yum.repos.d/citus-enterprise-microsoft.repo << EOF
    [packages-microsoft-com-citus-centos7]
    name=packages-microsoft-com-citus-centos7
    baseurl=https://packages.microsoft.com/yumrepos/citus-centos7/
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.microsoft.com/keys/microsoft.asc
    EOF

Redhat 8/CentOS 8
$$$$$$$$$$$$$$$$$

.. code:: bash

    sudo cat > /etc/yum.repos.d/citus-enterprise-microsoft.repo << EOF
    [packages-microsoft-com-citus-centos8]
    name=packages-microsoft-com-citus-centos8
    baseurl=https://packages.microsoft.com/yumrepos/citus-centos8/
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.microsoft.com/keys/microsoft.asc
    EOF

.. _sku_pgdg:

Install PostgreSQL from the official PostgreSQL package repositories
--------------------------------------------------------------------

If PostgreSQL is not yet installed, follow these instructions:
https://www.postgresql.org/download/

.. _sku_pkg:

Install the Citus Enterprise package
------------------------------------

Debian/Ubuntu
~~~~~~~~~~~~~

.. code:: bash

    sudo apt-get update
    # Change to postgresql-11-citus-enterprise-9.2 if you want to install Citus for
    # PostgreSQL 11
    sudo apt-get install -y postgresql-12-citus-enterprise-9.2

Redhat/CentOS
~~~~~~~~~~~~~

IMPORTANT: If upgrading from another Major or Minor Citus version, first
remove the old package

.. code:: bash

    # Change to citus-enterprise92_11 for PostgreSQL 11)
    sudo yum install -y citus-enterprise92_12

.. _sku_setup:

Run the Citus Enterprise setup
------------------------------

.. note::

  This is different from previous Citus Enterprise installation instructions.

Use ``citus-enterprise-pg-11-setup`` when installing for Postgres 11

.. code:: bash

    sudo citus-enterprise-pg-12-setup
    # Non-interactive version
    # IMPORTANT: you accept the license and encryption disclaimer here
    sudo CITUS_ACCEPT_LICENSE=YES \
         CITUS_ACCEPT_ENCRYPTION_DISCLAIMER=YES \
         CITUS_LICENSE_KEY=<INSERT LICENSE KEY HERE> \
         citus-enterprise-pg-12-setup

.. _sku_use:

Start using the new Citus Enterprise version
--------------------------------------------

For upgrades
~~~~~~~~~~~~

Follow the instructions in :ref:`upgrading_citus`, starting after the install
of the packages (the next step should be a restart of PostgreSQL)

For fresh installations
~~~~~~~~~~~~~~~~~~~~~~~

Debian/Ubuntu
$$$$$$$$$$$$$

.. code:: bash

    # preload citus extension
    sudo pg_conftool 12 main set shared_preload_libraries citus

Continue by following the standard multi-machine Debian/Ubuntu installation.
Start at step 3: :ref:`Configure connection and authentication
<post_enterprise_deb>`.

Redhat
$$$$$$

.. code:: bash

    # initialize system database (using RHEL 6 vs 7 method as necessary)
    sudo service postgresql-12 initdb || \
      sudo /usr/pgsql-12/bin/postgresql-12-setup initdb
    # preload citus extension
    echo "shared_preload_libraries = 'citus'" | \
      sudo tee -a /var/lib/pgsql/12/data/postgresql.conf

Continue by following the standard multi-machine Debian/Ubuntu installation.
Start at step 3: :ref:`Configure connection and authentication
<post_enterprise_rhel>`.


.. _sku_failover_pkg:

\(Optional\) Install the pg_auto_failover enterprise package
------------------------------------------------------------

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

.. _sku_failover_setup:

\(Optional\) Run the pg_auto_failover enterprise setup
------------------------------------------------------

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

.. _pgautofailover_sku_use:
