.. _master_node_failures:

Master Node Failures
#####################

The CitusDB master node maintains metadata tables to track all of the cluster nodes and the locations of the database shards on those nodes. The metadata tables are small (typically a few MBs in size) and do not change very often. This means that they can be replicated and quickly restored if the node ever experiences a failure. There are several options on how users can deal with master node failures.

1. **Use PostgreSQL streaming replication:** You can use PostgreSQL's streaming
replication feature to create a hot standby of the master node. Then, if the primary
master node fails, the standby can be promoted to the primary automatically to
serve queries to your cluster. For details on setting this up, please refer to the `PostgreSQL wiki <https://wiki.postgresql.org/wiki/Streaming_Replication>`_.

2. Since the metadata tables are small, users can use EBS volumes, or `PostgreSQL
backup tools <http://www.postgresql.org/docs/9.4/static/backup.html>`_ to backup the metadata. Then, they can easily
copy over that metadata to new nodes to resume operation.

3. CitusDB's metadata tables are simple and mostly contain text columns which
are easy to understand. So, in case there is no failure handling mechanism in
place for the master node, users can dynamically reconstruct this metadata from
shard information available on the worker nodes. To learn more about the metadata
tables and their schema, you can visit the :ref:`metadata_tables` section of our documentation.
