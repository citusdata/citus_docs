.. _transitioning_from_postgresql_to_citus:

Transitioning From PostgreSQL to Citus
#########################################

As Citus is a PostgreSQL extension, PostgreSQL users can start using Citus by simply installing the extension on their existing PostgreSQL database. Once you create the extension, you can create and use distributed tables through standard PostgreSQL interfaces while maintaining compatibility with existing PostgreSQL tools. Please look at :ref:`working_with_distributed_tables` for specific instructions.

To move your data from a PostgreSQL table to a distributed table, you can copy out the data into a csv file and then use the \stage command or the copy script to load it into a distributed table. Citus also provides the :ref:`master_append_table_to_shard` function for users who want to append their PostgreSQL tables to distributed tables directly. One thing to note as you transition from a single node to multiple nodes is that you should create your extensions, operators, user defined functions, and custom data types on all nodes.

If you have any questions or require assistance in scaling out your existing PostgreSQL installation, please get in touch with us at engage@citusdata.com.
