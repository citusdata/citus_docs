.. _minor_version_upgrades:

Minor Version Upgrades
#######################

Minor version upgrades in CitusDB are binary compatible. This means that you do not have to run pg_upgrade to upgrade between them. You can simply download and install the binaries for the new version and restart your server to upgrade to the new version.

Please note that these steps need to be run on all nodes in the cluster.

**1. Download and install CitusDB packages for the new version**

After downloading the new CitusDB package from our downloads page, you can install it using the
appropriate package manager for your operating system.

For rpm based packages:
	
::
    
    sudo rpm --install citusdb-4.0.1-1.x86_64.rpm

For debian packages

::

    sudo dpkg --install citusdb-4.0.1-1.amd64.deb

**2. Restart the CitusDB server**

Once you have installed the packages, you can restart the server and it will automatically start using the binaries of the newer version.

::

	/opt/citusdb/4.0/bin/pg_ctl -D /opt/citusdb/4.0/data -l logfile restart

