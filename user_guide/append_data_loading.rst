.. _append_data_loading:

Data Loading
############


CitusDB supports two methods to load data into your append distributed tables. The first one is suitable for bulk loads from CSV/TSV files and involves using the \stage command. For use cases requiring smaller, incremental data loads, CitusDB provides two user defined functions. We describe each of the methods and their usage below.

Bulk load using \stage
$$$$$$$$$$$$$$$$$$$$$$$

::

    SET shard_max_size TO '64MB';
    SET shard_replication_factor TO 1;
    \stage github_events from 'github_events-2015-01-01-0.csv' WITH CSV;

The \stage command is used to copy data from a file to a distributed table while handling replication and failures automatically. This command borrows its syntax from the `client-side \copy command <http://www.postgresql.org/docs/9.4/static/app-psql.html>`_ in PostgreSQL. Behind the covers, \stage first opens a connection to the master node and fetches candidate worker nodes to create new shards on. Then, the command connects to these worker nodes, creates at least one shard there, and uploads the data to the shards. The command then replicates these shards on other worker nodes till the replication factor is satisfied, and fetches statistics for these shards. Finally, the command stores the shard metadata with the master node.

CitusDB assigns a unique shard id to each new shard and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name 'tablename_shardid' where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. One can connect to the worker postgres instances to view or run commands on individual shards.

By default, the \stage command depends on two configuration entries for its behavior. These two entries are called shard_max_size and shard_replication_factor, and they live in postgresql.conf.

(1) **shard_max_size :-** shard_max_size determines the maximum size of a shard created using \stage, and defaults to 1 GB. If the file is larger than this parameter, \stage will break it up into multiple shards.
(2) **shard_replication_factor :-** This entry determines the number of nodes each shard gets replicated to, and defaults to two nodes. The ideal value for this parameter depends on the size of the cluster and rate of node failure. For example, you may want to increase the replication factor if you run large clusters and observe node failures on a more frequent basis.

Please note that you can load several files in parallel through separate database connections or from different nodes. It is also worth noting that \stage always creates at least one shard and does not append to existing shards. You can use the UDFs described below to append to previously created shards.

Incremental loads by appending to existing shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The \stage command always creates a new shard when it is used and is best suited for bulk loading of data. Using \stage to load smaller data increments will result in many small shards which might not be ideal. In order to allow smaller, incremental loads into append distributed tables, CitusDB has 2 user defined functions. They are master_create_empty_shard() and master_append_table_to_shard().

master_create_empty_shard() can be used to create new empty shards for a table. This function also replicates the empty shard to shard_replication_factor number of nodes like the \stage command.

master_append_table_to_shard() can be used to append the contents of a PostgreSQL table to an existing shard. This allows the user to control the shard to which the rows will be appended. It also returns the shard fill ratio which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created.

To use the above functionality, you can first insert incoming data into a regular PostgreSQL table. You can then create an empty shard using master_create_empty_shard(). Then, using master_append_table_to_shard(), the user can append the contents of the staging table to the specified shard, and then subsequently delete the data from the staging table. Once the shard fill ratio returned by the append function becomes close to 1, the user can create a new shard and start appending to the new one.

::


    SELECT * from master_create_empty_shard('github_events');
    master_create_empty_shard
    ---------------------------
                    102089
    (1 row)
    
    SELECT * from master_append_table_to_shard(102089, 'github_events_temp', 'master-101', 5432);
    master_append_table_to_shard 
    ------------------------------               
            0.100548
    (1 row)

Please note that it is not recommended to run master_create_empty_shard and
master_append_table_to_shard in the same transaction. This is because
master_create_empty_shard holds a lock on the shard till the end of transaction
and this can lead to reduced concurrency.

To learn more about the two UDFs, their arguments and usage, please visit the :ref:`user_defined_functions` section of the documentation.
