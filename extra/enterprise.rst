:orphan:

Installing Citus Enterprise Edition
===================================

.. _enterprise_debian:

Ubuntu or Debian
----------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Create a package tarball:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/deb.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

    sudo apt-get clean
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

    sudo pg_conftool 10 main set shared_preload_libraries citus

5. Continue by following the standard :ref:`multi-machine debian <post_enterprise_deb>` installation steps, **starting at step 3.**

.. _enterprise_rhel:

Fedora, CentOS, or Red Hat
--------------------------

1. Contact us to obtain a Citus Enterprise repository token. This token grants download access to the packages.

2. Create a package tarball:

  .. code-block:: bash

    # replace XYZ with your token
    curl https://install.citusdata.com/enterprise/rpm.sh | \
      sudo CITUS_REPO_TOKEN=XYZ bash

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
