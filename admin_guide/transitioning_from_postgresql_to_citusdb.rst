.. _transitioning_from_postgresql_to_citusdb:

Transitioning From PostgreSQL to CitusDB
#########################################

CitusDB can be used as a drop in replacement for PostgreSQL without making any changes at the application layer. Since CitusDB extends PostgreSQL, users can benefit from new PostgreSQL features and maintain compatibility with existing PostgreSQL tools.

Users can easily migrate from an existing PostgreSQL installation to CitusDB by copying out their data and then using the \stage command or the copy script to load in their data. CitusDB also provides the master_append_table_to_shard UDF for users who want to append their PostgreSQL tables into their distributed tables. Then, you can also create all your extensions, operators, user defined functions, and custom data types on your CitusDB cluster just as you would do with PostgreSQL.

Please get in touch with us at engage@citusdata.com if you want to scale out your existing PostgreSQL installation with CitusDB.

With this, we end our discussion regarding CitusDB administration. You can read more about the commands, user defined functions and configuration parameters in the :ref:`reference_index` section.
