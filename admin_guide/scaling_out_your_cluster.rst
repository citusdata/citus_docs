.. _scaling_out_cluster:

Scaling out your cluster
########################

CitusDB’s logical sharding based architecture allows you to scale out your cluster without any down time. This section describes how you can add nodes to your CitusDB cluster in order to improve query performance / scalability.

.. _adding_worker_node:

Adding a worker node
----------------------


CitusDB stores all the data for distributed tables on the worker nodes. Hence, if you want to scale out your cluster by adding more computing power, you can do so by adding a worker node.

To add a new node to the cluster, you first need to add the DNS name of that node to the pg_worker_list.conf file in your data directory on the master node.

Next, you can call the pg_reload_conf UDF on the master node to cause it to reload its configuration.

::

	select pg_reload_conf();

After this point, CitusDB will automatically start assigning new shards to that node. If you want to move existing shards to the newly added node, you can use the rebalance_table_shards UDF. This UDF will move the shards of the given table to make them evenly distributed among the worker nodes.

::

	select rebalance_table_shards('github_events');

Note: You need to have the shard rebalancer extension created to use this UDF.
::

    CREATE EXTENSION shard_rebalancer;


Adding a master node
----------------------

The CitusDB master node only stores metadata about the table shards and does not store any data. This means that all the computation is pushed down to the worker nodes and the master node does only final aggregations on the result of the workers. Therefore, it is not very likely that the master node becomes a bottleneck for read performance. Also, it is easy to boost up the master node by shifting to a more powerful machine.

However, in specific use cases where the master node becomes a performance bottleneck, users can add another master node to scale out the read performance. As the metadata tables are small (typically a few MBs in size), it is easy to copy over the metadata onto another node and sync it regularly. Once this is done, users can send their queries to any master node and scale out their reads. If your setup requires you to use multiple master nodes, please contact us at engage@citusdata.com.
