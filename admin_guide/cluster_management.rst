.. _cluster_management:

Cluster Management
###################

In this section, we discuss how you can manage your CitusDB cluster. This includes adding and removing nodes, dealing with node failures and upgrading your CitusDB cluster to a newer version. For moving shards across newly added nodes or replicating shards on failed nodes, users can use the shard rebalancer extension.

The shard rebalancer extension comes installed with the CitusDB contrib package. It mainly provides two functions for rebalancing / re-replicating shards for a distributed table. We discuss both the functions as and when relevant in the sections below. To learn more about these functions, their arguments and usage, you can visit the :ref:`cluster_management_functions` reference.

.. toctree::
   :hidden:

   scaling_out_your_cluster.rst
   dealing_with_node_failures.rst
   upgrading_citusdb.rst

