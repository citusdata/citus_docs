.. _dealing_with_node_failures:

Dealing With Node Failures
##########################

In this sub-section, we discuss how you can deal with node failures without incurring any downtime on your CitusDB cluster. We first discuss how CitusDB handles worker node failures automatically by maintaining multiple replicas of the data. We also describe how users can replicate their shards to bring them to the desired replication factor in case a node is down for a long time. Lastly, we discuss how you can setup redundancy and failure handling mechanisms for the master node.


.. toctree::
   :hidden:

   worker_node_failures.rst
   master_node_failures.rst
