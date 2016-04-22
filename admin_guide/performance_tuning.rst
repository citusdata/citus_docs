.. _performance_tuning:

Performance Tuning
##################

In this section, we describe how users can tune their CitusDB cluster to get
maximum performance for their queries. We begin by explaining how choosing the
right distribution column and method affects performance. We then describe how
you can first tune your database for high performance on one node and then scale
it out across all the CPUs in the cluster. In this section, we also discuss
several performance related configuration parameters wherever relevant.

.. toctree::
   :hidden:
   
   table_distribution_shards.rst
   postgresql_tuning.rst
   scaling_out_performance.rst
   distributed_query_performance_tuning.rst
