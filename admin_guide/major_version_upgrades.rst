.. _major_version_upgrades:

Major Version Upgrades
#######################

If you are upgrading from CitusDB 3.0 to CitusDB 4.0, then you can use the standard `PostgreSQL pg_upgrade <http://www.postgresql.org/docs/9.4/static/pgupgrade.html>`_ utility. pg_upgrade uses the fact that the on-disk representation of the data has probably not changed, and copies over the disk files as is, thus making the upgrade process faster. Apart from running pg_upgrade, there are 3 manual steps to be accounted for in order to update CitusDB.

1. Copy over pg_dist_* catalog tables.
2. Copy over pg_foreign_file/cached.
3. Set pg_dist_shardid_seq current sequence to max shard value.

The others are known pg_upgrade manual steps, i.e. manually updating configuration files, pg_hba etc.

We discuss the step by step process of upgrading the cluster below. Please note that you need to run the steps on all the nodes in the cluster. Some steps need to be run only on the master node and they are explicitly marked as such.

**1. Download and install CitusDB 4.0 on the node having the to-be-upgraded 3.0 data directory**

You can first download the new packages from our Downloads page. Then, you can
install it using the appropriate command for your operating system.

For rpm based packages:
::

    sudo rpm --install citusdb-4.0.1-1.x86_64.rpm
    sudo rpm --install citusdb-contrib-4.0.1-1.x86_64.rpm

For debian packages:
::

    sudo dpkg --install citusdb-4.0.1-1.amd64.deb
    sudo dpkg --install citusdb-contrib-4.0.1-1.amd64.deb

Note that the 4.0 package will install at /opt/citusdb/4.0.

**2. Setup environment variables for the data directories**

::

    export PGDATA4_0=/opt/citusdb/4.0/data
    export PGDATA3_0=/opt/citusdb/3.0/data

**3. Stop loading data on to that node**

If you are upgrading the master node, then you should stop all data-loading/appending
and staging before copying out the metadata. If data-loading continues after step 5 below,
then the metadata will be out of date.

**4. Copy out pg_dist catalog metadata from the 3.0 server (Only needed for master node)**
::

    COPY pg_dist_partition TO '/var/tmp/pg_dist_partition.data';
    COPY pg_dist_shard TO '/var/tmp/pg_dist_shard.data';
    COPY pg_dist_shard_placement TO '/var/tmp/pg_dist_shard_placement.data';

**5. Initialize a new data directory for 4.0**
::

    /opt/citusdb/4.0/bin/initdb $PGDATA4_0

You can ignore this step if you are using the standard data directory which CitusDB creates by default while installing the packages.

**6. Check upgrade compatibility**

:: 

	/opt/citusdb/4.0/bin/pg_upgrade -b /opt/citusdb/3.0/bin/ -B /opt/citusdb/4.0/bin/ -d $PGDATA3_0 -D $PGDATA4_0 --check

This should return **Clusters are compatible**. If this doesn't return that message, you need to stop and check what the error is.

Note: This may return the following warning if the 3.0 server has not been stopped. This warning is OK:
::

    *failure*
    Consult the last few lines of "pg_upgrade_server.log" for the probable cause of the failure.

**7. Shutdown the running 3.0 server**

::

	/opt/citusdb/3.0/bin/pg_ctl stop -D $PGDATA3_0

**8. Run pg_upgrade, removing the --check flag**

::

	/opt/citusdb/4.0/bin/pg_upgrade -b /opt/citusdb/3.0/bin/ -B /opt/citusdb/4.0/bin/ -d $PGDATA3_0 -D $PGDATA4_0

**9. Copy over pg_worker_list.conf (Only needed for master node)**

::

	cp $PGDATA3_0/pg_worker_list.conf $PGDATA4_0/pg_worker_list.conf

**10. Re-do changes to config settings in postgresql.conf and pg_hba.conf in the 4.0 data directory**

* listen_addresses
* shard_max_size, shard_replication_factor etc
* performance tuning parameters
* enabling connections

**11. Copy over the cached foreign data**

::

	cp -R $PGDATA3_0/pg_foreign_file/* $PGDATA4_0/pg_foreign_file/

**12.  Start the new 4.0 server**

::

	/opt/citusdb/4.0/bin/pg_ctl -D $PGDATA4_0 start

**13. Copy over pg_dist catalog tables to the new server using the 4.0 psql client (Only needed for master-node)**

::

    /opt/citusdb/4.0/bin/psql -d postgres -h localhost
    COPY pg_dist_partition FROM '/var/tmp/pg_dist_partition.data';
    COPY pg_dist_shard FROM '/var/tmp/pg_dist_shard.data';
    COPY pg_dist_shard_placement FROM '/var/tmp/pg_dist_shard_placement.data';

**14. Restart the sequence pg_dist_shardid_seq (Only needed for master-node)**

::

	SELECT setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid) AS max_shard_id FROM pg_dist_shard)+1, false);

This is needed since the sequence value doesn't get copied over. So we restart the sequence from the largest shardid (+1 to avoid collision). This will come into play when staging data, not when querying data.

If you are using hash partitioned tables, then this step may return an error :

::
    
    ERROR:  setval: value 100** is out of bounds for sequence "pg_dist_shardid_seq" (102008..9223372036854775807)

You can ignore this error and continue with the process below.

**15. Ready to run queries/create tables/load data**
 
At this step, you have successfully completed the upgrade process. You can run queries, create new tables or add data to existing tables. Once everything looks good, the old 3.0 data directory can be deleted.


Running in a mixed mode
------------------------
For users who don’t want to take a cluster down and upgrade all nodes at the same time, there is the possibility of running in a mixed 3.0 / 4.0 mode. To do so, you can first upgrade the master node. Then, you can upgrade the worker nodes one at a time. This way you can upgrade the cluster with no downtime.
