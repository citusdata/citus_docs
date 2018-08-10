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
    # (the rebalancer package pulls in other necessary packages)
    sudo apt-get install -y postgresql-10-citus-rebalancer-7.5

    # preload citus extension
    sudo pg_conftool 10 main set shared_preload_libraries citus

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
    # (the rebalancer package pulls in other necessary packages)
    sudo apt-get install -y --download-only postgresql-10-citus-rebalancer-7.5

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
    sudo pg_conftool 10 main set shared_preload_libraries citus

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
    # (the rebalancer package pulls in other necessary packages)
    sudo yum install -y citus-rebalancer75_10

    # initialize system database (using RHEL 6 vs 7 method as necessary)
    sudo service postgresql-10 initdb || \
      sudo /usr/pgsql-10/bin/postgresql-10-setup initdb
    # preload citus extension
    echo "shared_preload_libraries = 'citus'" | \
      sudo tee -a /var/lib/pgsql/10/data/postgresql.conf

3. Continue by following the standard :ref:`multi-machine rhel <post_enterprise_rhel>` installation steps, **starting at step 3.**

Fedora, CentOS, or Red Hat without Internet Access
--------------------------------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Create a package tarball:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/rpm.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    # (the rebalancer package pulls in other necessary packages)
    sudo yum install --downloadonly --downloaddir=. citus-rebalancer75_10

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
    sudo service postgresql-10 initdb || \
      sudo /usr/pgsql-10/bin/postgresql-10-setup initdb
    # preload citus extension
    echo "shared_preload_libraries = 'citus'" | \
      sudo tee -a /var/lib/pgsql/10/data/postgresql.conf

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
    # (the rebalancer package pulls in other necessary packages)
    sudo apt-get install -y postgresql-10-citus-rebalancer-X.Y

    # substitute X.Y with the version currently installed ^^^^^

4. Restart the database.

  .. code-block:: bash

    sudo service postgresql restart

5. Update the Citus extension and initialize the Shard Rebalancer

   .. code-block:: bash

    sudo -i -u postgres psql -c "ALTER EXTENSION citus UPDATE;"
    sudo -i -u postgres psql -c "CREATE EXTENSION shard_rebalancer;"


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
    sudo yum remove -y citusXY_10

    # Install enterprise packages
    # substitute XY with the version previously installed
    # (the rebalancer package pulls in other necessary packages)
    sudo yum install -y citus-rebalancerXY_10

4. Restart the database.

  .. code-block:: bash

    sudo service postgresql-10 restart

5. Update the Citus extension and initialize the Shard Rebalancer

   .. code-block:: bash

    sudo -i -u postgres psql -c "ALTER EXTENSION citus UPDATE;"
    sudo -i -u postgres psql -c "CREATE EXTENSION shard_rebalancer;"
