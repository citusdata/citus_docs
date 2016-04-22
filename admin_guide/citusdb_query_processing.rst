.. _citusdb_query_processing:

CitusDB Query Processing
########################

CitusDB consists of a master node and multiple worker nodes. The data is sharded and replicated on the worker nodes while the master node stores only metadata about these shards. All queries issued to the cluster are executed via the master node. The master node partitions the query into smaller query fragments where each query fragment can be run independently on a shard. The master node then assigns the query fragments to worker nodes, oversees their execution, merges their results, and returns the final result to the user. The query processing architecture can be described in brief by the diagram below.

.. image:: ../images/citus-high-level-arch.png

CitusDB’s query processing pipeline involves the two components:

* **Distributed Query Planner and Executor**
* **PostgreSQL Planner and Executor**

We discuss them in greater detail in the subsequent sections.

.. toctree::
   :hidden:

   distributed_query_planner.rst
   distributed_query_executor.rst
   postgresql_planner_executor.rst
    

