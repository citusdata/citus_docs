.. _worker_node_failures:

Worker Node Failures
#####################


CitusDB can easily tolerate worker node failures because of its logical sharding-based architecture. While loading data, CitusDB allows you to specify the replication factor to provide desired availability for your data. In face of worker node failures, CitusDB automatically switches to these replicas to serve your queries and also provides options to bring back your cluster to the same level of availability. It also issues warnings like below on the master node so that users can take note of node failures and take actions accordingly.

::

    WARNING:  could not connect to node localhost:9700

On seeing such warnings, the first step would be to remove the failed worker node from the pg_worker_list.conf file in the data directory.

::

    vi /opt/citusdb/4.0/data/pg_worker_list.conf

Then, you can reload the configuration so that the master node picks up the desired configuration changes.

::

	SELECT pg_reload_conf();

After this step, CitusDB will stop assigning tasks or storing data on the failed node. Then, you can log into the failed worker node and inspect the cause of the failure. Depending on the type of failure, you can take actions as described below.

Temporary Node Failures
------------------------

Temporary node failures can occur due to high load, maintenance work on the node, or due to network connectivity issues. As these failures are for a short duration, the primary concern in such cases is to be able to generate query responses even in face of failures.

If the node failure you are seeing is temporary, you can simply remove the worker node from pg_worker_list.conf (as discussed above).
CitusDB will then automatically tackle these failures by re-routing the work to healthy nodes. If CitusDB is not able to connect a worker node,
it automatically assigns that task to another worker node having a copy of that shard. If the failure occurs mid-query, CitusDB does not re-run the whole query but assigns only the failed tasks / query fragments leading to faster responses in face of failures.

Once the node is back up, you can add it to the pg_worker_list.conf and reload the configuration.

Permanent Node Failures / Node decommissioning
-----------------------------------------------

If you realize that the node failure is permanent, CitusDB will continue to deal with the node failure by re-routing queries to the active nodes in the cluster. However, this may not be ideal for the long-term and in such cases, users may desire to retain the same level of replication so that their application can tolerate more failures. To do this, users can re-replicate the shards using the replicate_table_shards UDF after removing the failed / decommissioned node from pg_worker_list.conf. The replicate_table_shards() function replicates the shards of a table so they all reach the configured replication factor.

::

    select replicate_table_shards('github_events');

Note: You need to have the shard rebalancer extension installed to use this UDF.
::

    CREATE EXTENSION shard_rebalancer;

If you want to add a new node to the cluster to replace the failed node, you can follow the instructions described in the :ref:`adding_worker_node` section.

