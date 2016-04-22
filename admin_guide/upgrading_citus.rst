.. _upgrading_citus:

Upgrading to Citus 5
#######################

This section describes how you can upgrade your existing Citus installation to Citus 5.0.

If you are upgrading from CitusDB 4.0 to Citus 5.0, you can use the standard `PostgreSQL pg_upgrade <http://www.postgresql.org/docs/9.5/static/pgupgrade.html>`_ utility. pg_upgrade uses the fact that the on-disk representation of the data has probably not changed, and copies over the disk files as is, thus making the upgrade process faster.

Citus 5.0 is not a standalone application but a PostgreSQL extension. Therefore, you should first install `PostgreSQL 9.5 <http://www.postgresql.org/download/>`_ before installing Citus 5.0.

Apart from running pg_upgrade, there are 3 manual steps to be accounted for in order to update Citus.

1. Create and configure Citus extension.
2. Copy over Citus medadata tables.
3. Set pg_dist_shardid_seq current sequence to max shard value.

The others are known pg_upgrade manual steps, i.e. manually updating configuration files, pg_hba etc.

We discuss the step by step process of upgrading the cluster below. Please note that you need to run the steps on all the nodes in the cluster. Some steps need to be run only on the master and they are explicitly marked as such.

**1. Download and install Citus 5.0 on the server having the to-be-upgraded 4.0 data directory**

Download and install PostgreSQL 9.5.x from http://www.postgresql.org/download/.

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:
    
    ::
        
        export PATH=/usr/lib/postgresql/9.5/:$PATH

You can then download and install the new Citus packages from our Downloads page. Please visit the :ref:`production` section for specific instructions.

Note that the Citus 5.0 extension will be installed at the PostgreSQL install location.

**2. Setup environment variables for the data directories**

Please set appropriate values for data location like below. This makes accessing data directories in subsequent commands easier.

::

    export PGDATA5_0=/usr/lib/postgresql/9.5/data
    export PGDATA4_0=/opt/citusdb/4.0/data


**3. Stop loading data on to that instance**

If you are upgrading the master, then you should stop all data-loading/appending
and staging before copying out the metadata. If data-loading continues after step 4 below,
then the metadata will be out of date.

**4. Copy out pg_dist catalog metadata from the 4.0 server (Only needed for master)**
::

    COPY pg_dist_partition TO '/var/tmp/pg_dist_partition.data';
    COPY pg_dist_shard TO '/var/tmp/pg_dist_shard.data';
    COPY pg_dist_shard_placement TO '/var/tmp/pg_dist_shard_placement.data';

**5. Initialize a new data directory for 5.0**
::

    initdb -D $PGDATA5_0

Note: On some platforms, PostgreSQL creates a data directory by default during installation. You can ignore this step if you want to use that data directory.

**6. Check upgrade compatibility**

:: 

	pg_upgrade -b /opt/citusdb/4.0/bin/ -B /usr/lib/postgresql/9.5/bin/ -d $PGDATA4_0 -D $PGDATA5_0 --check

This should return **Clusters are compatible**. If this doesn't return that message, you need to stop and check what the error is.

Note: This may return the following warning if the 4.0 server has not been stopped. This warning is OK:

::

    *failure*
    Consult the last few lines of "pg_upgrade_server.log" for the probable cause of the failure.

**7. Shutdown the running 4.0 server**

::

	/opt/citusdb/4.0/bin/pg_ctl stop -D $PGDATA4_0

**8. Run pg_upgrade, remove the --check flag**

::

    pg_upgrade -b /opt/citusdb/4.0/bin/ -B /usr/lib/postgresql/9.5/bin/ -d $PGDATA4_0 -D $PGDATA5_0 

**9. Copy over pg_worker_list.conf (Only needed for master)**

::

	cp $PGDATA4_0/pg_worker_list.conf $PGDATA5_0/pg_worker_list.conf

**10. Re-do changes to config settings in postgresql.conf and pg_hba.conf in the 5.0 data directory**

* listen_addresses
* performance tuning parameters
* enabling connections
* Copy all non-default settings below **DISTRIBUTED DATABASE** section (eg. shard_max_size, shard_replication_factor etc) to the end of the new postgresql.conf. Also note that for usage with Citus 5.0, each setting name must be prefixed with "citus". i.e. **shard_max_size** becomes **citus.shard_max_size**.

**11. Add citus to shared_preload_libraries in postgresql.conf**

::

    vi $PGDATA5_0/postgresql.conf

::

    shared_preload_libraries = 'citus'

Make sure **citus** is the first extension if there are more extensions you want to add there.

**12.  Start the new 5.0 server**

::

	pg_ctl -D $PGDATA5_0 start

**13. Connect to postgresql instance and create citus extension**

::

    psql -d postgres -h localhost
    create extension citus;


**14. Copy over pg_dist catalog tables to the new server using the PostgreSQL 9.5.x psql client (Only needed for master)**

::

    psql -d postgres -h localhost
    COPY pg_dist_partition FROM '/var/tmp/pg_dist_partition.data';
    COPY pg_dist_shard FROM '/var/tmp/pg_dist_shard.data';
    COPY pg_dist_shard_placement FROM '/var/tmp/pg_dist_shard_placement.data';

**15. Restart the sequence pg_dist_shardid_seq (Only needed for master)**

::

	SELECT setval('pg_catalog.pg_dist_shardid_seq', (SELECT MAX(shardid) AS max_shard_id FROM pg_dist_shard)+1, false);

This is needed since the sequence value doesn't get copied over. So we restart the sequence from the largest shardid (+1 to avoid collision). This will come into play when staging data, not when querying data.

If you are using hash distributed tables, then this step may return an error :

::
    
    ERROR:  setval: value 100** is out of bounds for sequence "pg_dist_shardid_seq" (102008..9223372036854775807)

You can ignore this error and continue with the process below.

**16. Ready to run queries/create tables/load data**
 
At this step, you have successfully completed the upgrade process. You can run queries, create new tables or add data to existing tables. Once everything looks good, the old 4.0 data directory can be deleted.


**Running in a mixed mode**

For users who don’t want to take a cluster down and upgrade all nodes at the same time, there is the possibility of running in a mixed 4.0 / 5.0 mode. To do so, you can first upgrade the master. Then, you can upgrade the workers one at a time. This way you can upgrade the cluster with no downtime. However, we recommend using 5.0 version in whole cluster.
