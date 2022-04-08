.. _user_defined_functions:

Citus Utility Functions
=======================

This section contains reference information for the User Defined Functions provided by Citus. These functions help in providing additional distributed functionality to Citus other than the standard SQL commands.

Table and Shard DDL
-------------------
.. _create_distributed_table:

create_distributed_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The create_distributed_table() function is used to define a distributed table
and create its shards if it's a hash-distributed table. This function takes in
a table name, the distribution column and an optional distribution method and
inserts appropriate metadata to mark the table as distributed. The function
defaults to 'hash' distribution if no distribution method is specified. If the
table is hash-distributed, the function also creates worker shards based on the
shard count configuration value. If the table contains any rows, they are
automatically distributed to worker nodes.

Arguments
************************

**table_name:** Name of the table which needs to be distributed.

**distribution_column:** The column on which the table is to be distributed.

**colocate_with:** (Optional) include current table in the co-location group of another table. By default tables are co-located when they are distributed by columns of the same type with the same shard count.
If you want to break this colocation later, you can use :ref:`update_distributed_table_colocation <update_distributed_table_colocation>`. Possible values for :code:`colocate_with` are :code:`default`, :code:`none` to start a new co-location group, or the name of another table to co-locate with that table.  (See :ref:`colocation_groups`.)

Keep in mind that the default value of ``colocate_with`` does implicit co-location. As :ref:`colocation` explains, this can be a great thing when tables are related or will be joined. However, when two tables are unrelated but happen to use the same datatype for their distribution columns, accidentally co-locating them can decrease performance during :ref:`shard rebalancing <shard_rebalancing>`. The table shards will be moved together unnecessarily in a "cascade."
If you want to break this implicit colocation, you can use :ref:`update_distributed_table_colocation <update_distributed_table_colocation>`.

If a new distributed table is not related to other tables, it's best to specify ``colocate_with => 'none'``.

**shard_count:** (Optional) the number of shards to create for the new distributed table. When specifying ``shard_count`` you can't specify a value of ``colocate_with`` other than ``none``. To change the shard count of an existing table or colocation group, use the :ref:`alter_distributed_table` function.

Possible values for ``shard_count`` are between 1 and 64000. For guidance on choosing the optimal value, see :ref:`prod_shard_count`.

Return Value
********************************

N/A

Example
*************************

This example informs the database that the github_events table should be distributed by hash on the repo_id column.

.. code-block:: postgresql

  SELECT create_distributed_table('github_events', 'repo_id');

  -- alternatively, to be more explicit:
  SELECT create_distributed_table('github_events', 'repo_id',
                                  colocate_with => 'github_repo');

For more examples, see :ref:`ddl`.

.. _truncate_local_data_after_distributing_table:

truncate_local_data_after_distributing_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Truncate all local rows after distributing a table, and prevent constraints from failing due to outdated local records. The truncation cascades to tables having a foreign key to the designated table. If the referring tables are not themselves distributed then truncation is forbidden until they are, to protect referential integrity:

::

  ERROR:  cannot truncate a table referenced in a foreign key constraint by a local table

Truncating local coordinator node table data is safe for distributed tables because their rows, if they have any, are copied to worker nodes during distribution.

Arguments
************************

**table_name:** Name of the distributed table whose local counterpart on the coordinator node should be truncated.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  -- requires that argument is a distributed table
  SELECT truncate_local_data_after_distributing_table('public.github_events');

.. _undistribute_table:

undistribute_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The undistribute_table() function undoes the action of
:ref:`create_distributed_table` or :ref:`create_reference_table`.
Undistributing moves all data from shards back into a local table on the
coordinator node (assuming the data can fit), then deletes the shards.

Citus will not undistribute tables that have -- or are referenced by -- foreign
keys, unless the `cascade_via_foreign_keys` argument is set to true.
If this argument is false (or omitted), then you must manually drop the offending foreign
key constraints before undistributing.

Arguments
************************

**table_name:** Name of the distributed or reference table to undistribute.

**cascade_via_foreign_keys:** (Optional) When this argument set to "true," undistribute_table also
undistributes all tables that are related to **table_name** through foreign keys. Use caution with
this parameter, because it can potentially affect many tables.


Return Value
********************************

N/A

Example
*************************

This example distributes a ``github_events`` table and then undistributes it.

.. code-block:: postgresql

  -- first distribute the table
  SELECT create_distributed_table('github_events', 'repo_id');

  -- undo that and make it local again
  SELECT undistribute_table('github_events');


.. _alter_distributed_table:

alter_distributed_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The alter_distributed_table() function can be used to change the distribution
column, shard count or colocation properties of a distributed table.

Arguments
************************

**table_name:** Name of the distributed table that will be altered.

**distribution_column:** (Optional) Name of the new distribution column.

**shard_count:** (Optional) The new shard count.

**colocate_with:** (Optional) The table that the current distributed table will
be colocated with.  Possible values are ``default``, ``none`` to start a new
colocation group, or the name of another table with which to colocate.

**cascade_to_colocated:** (Optional) When this argument is set to "true",
``shard_count`` and ``colocate_with`` changes will also be applied to all of
the tables that were previously colocated with the table, and the colocation
will be preserved. If it is "false", the current colocation of this table will
be broken.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  -- change distribution column
  SELECT alter_distributed_table('github_events', distribution_column:='event_id');

  -- change shard count of all tables in colocation group
  SELECT alter_distributed_table('github_events', shard_count:=6, cascade_to_colocated:=true);

  -- change colocation
  SELECT alter_distributed_table('github_events', colocate_with:='another_table');


.. _alter_table_set_access_method:

alter_table_set_access_method
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The alter_table_set_access_method() function changes access method of a table
(e.g. heap or :ref:`columnar <columnar>`).

Arguments
************************

**table_name:** Name of the table whose access method will change.

**access_method:** Name of the new access method.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  SELECT alter_table_set_access_method('github_events', 'columnar');

.. _remove_local_tables_from_metadata:

remove_local_tables_from_metadata
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The remove_local_tables_from_metadata() function removes local tables
from Citus' metadata that no longer need to be there. (See
:ref:`enable_local_ref_fkeys`.)

Usually if a local table is in Citus' metadata, there's a reason, such as
the existence of foreign keys between the table and a reference table.
However, if ``enable_local_reference_foreign_keys`` is disabled, Citus
will no longer manage metadata in that situation, and unnecessary
metadata can persist until manually cleaned.

Arguments
************************

N/A

Return Value
********************************

N/A

.. _create_reference_table:

create_reference_table
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The create_reference_table() function is used to define a small reference or
dimension table. This function takes in a table name, and creates a distributed
table with just one shard, replicated to every worker node.

Arguments
************************

**table_name:** Name of the small dimension or reference table which needs to be distributed.


Return Value
********************************

N/A

Example
*************************
This example informs the database that the nation table should be defined as a
reference table

.. code-block:: postgresql

	SELECT create_reference_table('nation');

.. _mark_tables_colocated:

mark_tables_colocated
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The mark_tables_colocated() function takes a distributed table (the source), and a list of others (the targets), and puts the targets into the same co-location group as the source. If the source is not yet in a group, this function creates one, and assigns the source and targets to it.

Usually colocating tables ought to be done at table distribution time via the ``colocate_with`` parameter of :ref:`create_distributed_table`. But ``mark_tables_colocated`` can take care of it if necessary.

If you want to break colocation of a table, you can use :ref:`update_distributed_table_colocation <update_distributed_table_colocation>`.

Arguments
************************

**source_table_name:** Name of the distributed table whose co-location group the targets will be assigned to match.

**target_table_names:** Array of names of the distributed target tables, must be non-empty. These distributed tables must match the source table in:

  * distribution method
  * distribution column type
  * shard count

Failing this, Citus will raise an error. For instance, attempting to colocate tables ``apples`` and ``oranges`` whose distribution column types differ results in:

::

  ERROR:  cannot colocate tables apples and oranges
  DETAIL:  Distribution column types don't match for apples and oranges.

Return Value
********************************

N/A

Example
*************************

This example puts ``products`` and ``line_items`` in the same co-location group as ``stores``. The example assumes that these tables are all distributed on a column with matching type, most likely a "store id."

.. code-block:: postgresql

  SELECT mark_tables_colocated('stores', ARRAY['products', 'line_items']);

.. _update_distributed_table_colocation:

update_distributed_table_colocation
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The update_distributed_table_colocation() function is used to update colocation
of a distributed table. This function can also be used to break colocation of a 
distributed table. Citus will implicitly colocate two tables if the distribution
column is the same type, this can be useful if the tables are related and will 
do some joins. If table A and B are colocated, and table A gets rebalanced, table B 
will also be rebalanced. If table B does not have a replica identity, the rebalance will 
fail. Therefore, this function can be useful breaking the implicit colocation in that case.

Note that this function does not move any data around physically.

Arguments
************************

**table_name:** Name of the table colocation of which will be updated.

**colocate_with:** The table to which the table should be colocated with.

If you want to break the colocation of a table, you should specify ``colocate_with => 'none'``.

Return Value
********************************

N/A

Example
*************************

This example shows that colocation of ``table A`` is updated as colocation of ``table B``.

.. code-block:: postgresql

  SELECT update_distributed_table_colocation('A', colocate_with => 'B');


Assume that ``table A`` and ``table B`` are colocated( possibily implicitly), if you want to break the colocation:

.. code-block:: postgresql

  SELECT update_distributed_table_colocation('A', colocate_with => 'none');

Now, assume that ``table A``, ``table B``, ``table C`` and ``table D`` are colocated and you want to colocate ``table A`` 
and ``table B`` together, and ``table C`` and ``table D`` together:

.. code-block:: postgresql

  SELECT update_distributed_table_colocation('C', colocate_with => 'none');
  SELECT update_distributed_table_colocation('D', colocate_with => 'C');

If you have a hash distributed table named ``none`` and you want to update its colocation, you can do:

.. code-block:: postgresql

  SELECT update_distributed_table_colocation('"none"', colocate_with => 'some_other_hash_distributed_table');

.. _create_distributed_function:

create_distributed_function
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Propagates a function from the coordinator node to workers, and marks it for
distributed execution. When a distributed function is called on the
coordinator, Citus uses the value of the "distribution argument" to pick a
worker node to run the function. Executing the function on workers increases
parallelism, and can bring the code closer to data in shards for lower latency.

Note that the Postgres search path is not propagated from the coordinator to
workers during distributed function execution, so distributed function code
should fully-qualify the names of database objects. Also notices emitted by
the functions will not be displayed to the user.

Arguments
************************

**function_name:** Name of the function to be distributed. The name must
include the function's parameter types in parentheses, because multiple
functions can have the same name in PostgreSQL. For instance, ``'foo(int)'`` is
different from ``'foo(int, text)'``.

**distribution_arg_name:** (Optional) The argument name by which to distribute.
For convenience (or if the function arguments do not have names), a positional
placeholder is allowed, such as ``'$1'``. If this parameter is not specified,
then the function named by ``function_name`` is merely created on the workers.
If worker nodes are added in the future the function will automatically be
created there too.

**colocate_with:** (Optional) When the distributed function reads or writes to
a distributed table (or more generally :ref:`colocation_groups`), be sure to
name that table using the ``colocate_with`` parameter. This ensures that each
invocation of the function runs on the worker node containing relevant shards.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  -- an example function which updates a hypothetical
  -- event_responses table which itself is distributed by event_id
  CREATE OR REPLACE FUNCTION
    register_for_event(p_event_id int, p_user_id int)
  RETURNS void LANGUAGE plpgsql AS $fn$
  BEGIN
    INSERT INTO event_responses VALUES ($1, $2, 'yes')
    ON CONFLICT (event_id, user_id)
    DO UPDATE SET response = EXCLUDED.response;
  END;
  $fn$;

  -- distribute the function to workers, using the p_event_id argument
  -- to determine which shard each invocation affects, and explicitly
  -- colocating with event_responses which the function updates
  SELECT create_distributed_function(
    'register_for_event(int, int)', 'p_event_id',
    colocate_with := 'event_responses'
  );

.. _alter_columnar_table_set:

alter_columnar_table_set
$$$$$$$$$$$$$$$$$$$$$$$$

The alter_columnar_table_set() function changes settings on a :ref:`columnar
table <columnar>`. Calling this function on a non-columnar table gives an
error. All arguments except the table name are optional.

To view current options for all columnar tables, consult this table:

.. code-block:: postgresql

  SELECT * FROM columnar.options;

The default values for columnar settings for newly-created tables can be
overridden with these GUCs:

* columnar.compression
* columnar.compression_level
* columnar.stripe_row_count
* columnar.chunk_row_count

Arguments
************************

**table_name:** Name of the columnar table.

**chunk_row_count:** (Optional) The maximum number of rows per chunk for
newly-inserted data. Existing chunks of data will not be changed and may have
more rows than this maximum value. The default value is 10000.

**stripe_row_count:** (Optional) The maximum number of rows per stripe for
newly-inserted data. Existing stripes of data will not be changed and may have
more rows than this maximum value. The default value is 150000.

**compression:** (Optional) ``[none|pglz|zstd|lz4|lz4hc]`` The compression type
for newly-inserted data. Existing data will not be recompressed or
decompressed. The default and generally suggested value is zstd (if support has
been compiled in).

**compression_level:** (Optional) Valid settings are from 1 through 19. If the
compression method does not support the level chosen, the closest level will be
selected instead.

Return Value
********************************

N/A

Example
*************************

.. code-block:: postgresql

  SELECT alter_columnar_table_set(
    'my_columnar_table',
    compression => 'none',
    stripe_row_count => 10000);

.. _create_time_partitions:

create_time_partitions
$$$$$$$$$$$$$$$$$$$$$$

The create_time_partitions() function creates partitions of a given interval to
cover a given range of time.

Arguments
*********

**table_name:** (regclass) table for which to create new partitions. The table
must be partitioned on one column, of type date, timestamp, or timestamptz.

**partition_interval:** an interval of time, such as ``'2 hours'``, or ``'1
month'``, to use when setting ranges on new partitions.

**end_at:** (timestamptz) create partitions up to this time. The last partition
will contain the point end_at, and no later partitions will be created.

**start_from:** (timestamptz, optional) pick the first partition so that it
contains the point start_from. The default value is ``now()``.

Return Value
************

True if it needed to create new partitions, false if they all existed already.

Example
*******

.. code-block:: postgresql

   -- create a year's worth of monthly partitions
   -- in table foo, starting from the current time

   SELECT create_time_partitions(
     table_name         := 'foo',
     partition_interval := '1 month',
     end_at             := now() + '12 months'
   );

.. _drop_old_time_partitions:

drop_old_time_partitions
$$$$$$$$$$$$$$$$$$$$$$$$

The drop_old_time_partitions() function removes all partitions whose intervals
fall before a given timestamp. In addition to using this function, you might
consider :ref:`alter_old_partitions_set_access_method` to compress the old
partitions with columnar storage.

Arguments
*********

**table_name:** (regclass) table for which to remove partitions. The table
must be partitioned on one column, of type date, timestamp, or timestamptz.

**older_than:** (timestamptz) drop partitions whose upper range is less than
or equal to older_than.

Return Value
************

N/A

Example
*******

.. code-block:: postgresql

   -- drop partitions that are over a year old

   CALL drop_old_time_partitions('foo', now() - interval '12 months');

.. _alter_old_partitions_set_access_method:

alter_old_partitions_set_access_method
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

In a :ref:`timeseries` use case, tables are often partitioned by time, and old
partitions are compressed into read-only columnar storage.

Arguments
*********

**parent_table_name:** (regclass) table for which to change partitions. The
table must be partitioned on one column, of type date, timestamp, or
timestamptz.

**older_than:** (timestamptz) change partitions whose upper range is less than
or equal to older_than.

**new_access_method:** (name) either `'heap'` for row-based storage, or
`'columnar'` for columnar storage.

Return Value
************

N/A

Example
*******

.. code-block:: postgresql

  CALL alter_old_partitions_set_access_method(
    'foo', now() - interval '6 months',
    'columnar'
  );

Metadata / Configuration Information
------------------------------------------------------------------------

.. _citus_add_node:

citus_add_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The citus_add_node() function registers a new node addition in the cluster in
the Citus metadata table pg_dist_node. It also copies reference tables to the new node.

If running ``citus_add_node`` on a single-node cluster, be sure to run
:ref:`set_coordinator_host` first.

Arguments
************************

**nodename:** DNS name or IP address of the new node to be added.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

**groupid:** A group of one primary server its secondary servers, relevant only
for streaming replication. Be sure to set ``groupid`` to a value greater than
zero, since zero is reserved for the coordinator node. The default is -1.

**noderole:** Whether it is 'primary' or 'secondary'. Default 'primary'

**nodecluster:** The cluster name. Default 'default'

Return Value
******************************

The nodeid column from the newly inserted row in :ref:`pg_dist_node <pg_dist_node>`.

Example
***********************

.. code-block:: postgresql

    select * from citus_add_node('new-node', 12345);
     citus_add_node
    -----------------
                   7
    (1 row)

.. _citus_update_node:

citus_update_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The citus_update_node() function changes the hostname and port for a node registered in the Citus metadata table :ref:`pg_dist_node <pg_dist_node>`.

Arguments
************************

**node_id:** id from the pg_dist_node table.

**node_name:** updated DNS name or IP address for the node.

**node_port:** the port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

.. code-block:: postgresql

    select * from citus_update_node(123, 'new-address', 5432);

.. _citus_set_node_property:

citus_set_node_property
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The citus_set_node_property() function changes properties in the Citus metadata table :ref:`pg_dist_node <pg_dist_node>`. Currently it can change only the ``shouldhaveshards`` property.

Arguments
************************

**node_name:** DNS name or IP address for the node.

**node_port:** the port on which PostgreSQL is listening on the worker node.

**property:** the column to change in ``pg_dist_node``, currently only ``shouldhaveshard`` is supported.

**value:** the new value for the column.

Return Value
******************************

N/A

Example
***********************

.. code-block:: postgresql

    SELECT * FROM citus_set_node_property('localhost', 5433, 'shouldhaveshards', false);

.. _citus_add_inactive_node:

citus_add_inactive_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The :code:`citus_add_inactive_node` function, similar to :ref:`citus_add_node`,
registers a new node in :code:`pg_dist_node`. However, it marks the new
node as inactive, meaning no shards will be placed there. Also it does
*not* copy reference tables to the new node.

Arguments
************************

**nodename:** DNS name or IP address of the new node to be added.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

**groupid:** A group of one primary server and zero or more secondary
servers, relevant only for streaming replication.  Default -1

**noderole:** Whether it is 'primary' or 'secondary'. Default 'primary'

**nodecluster:** The cluster name. Default 'default'

Return Value
******************************

The nodeid column from the newly inserted row in :ref:`pg_dist_node <pg_dist_node>`.

Example
***********************

.. code-block:: postgresql

    select * from citus_add_inactive_node('new-node', 12345);
     citus_add_inactive_node
    --------------------------
                            7
    (1 row)

.. _citus_activate_node:

citus_activate_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The :code:`citus_activate_node` function marks a node as active in the
Citus metadata table :code:`pg_dist_node` and copies reference tables to
the node. Useful for nodes added via :ref:`citus_add_inactive_node`.

Arguments
************************

**nodename:** DNS name or IP address of the new node to be added.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

The nodeid column from the newly inserted row in :ref:`pg_dist_node <pg_dist_node>`.

Example
***********************

.. code-block:: postgresql

    select * from citus_activate_node('new-node', 12345);
     citus_activate_node
    ----------------------
                        7
    (1 row)

citus_disable_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The :code:`citus_disable_node` function is the opposite of
:code:`citus_activate_node`. It marks a node as inactive in
the Citus metadata table :code:`pg_dist_node`, removing it from
the cluster temporarily. The function also deletes all reference table
placements from the disabled node. To reactivate the node, just run
:code:`citus_activate_node` again.

Arguments
************************

**nodename:** DNS name or IP address of the node to be disabled.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

.. code-block:: postgresql

    select * from citus_disable_node('new-node', 12345);

.. _citus_add_secondary_node:

citus_add_secondary_node
$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The citus_add_secondary_node() function registers a new secondary
node in the cluster for an existing primary node. It updates the Citus
metadata table pg_dist_node.

Arguments
************************

**nodename:** DNS name or IP address of the new node to be added.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

**primaryname:** DNS name or IP address of the primary node for this secondary.

**primaryport:** The port on which PostgreSQL is listening on the primary node.

**nodecluster:** The cluster name. Default 'default'

Return Value
******************************

The nodeid column for the secondary node, inserted row in :ref:`pg_dist_node <pg_dist_node>`.

Example
***********************

.. code-block:: postgresql

    select * from citus_add_secondary_node('new-node', 12345, 'primary-node', 12345);
     citus_add_secondary_node
    ---------------------------
                             7
    (1 row)


citus_remove_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

    This function requires database superuser access to run.

The citus_remove_node() function removes the specified node from the
pg_dist_node metadata table. This function will error out if there
are existing shard placements on this node. Thus, before using this
function, the shards will need to be moved off that node.

Arguments
************************

**nodename:** DNS name of the node to be removed.

**nodeport:** The port on which PostgreSQL is listening on the worker node.

Return Value
******************************

N/A

Example
***********************

.. code-block:: postgresql

    select citus_remove_node('new-node', 12345);
     citus_remove_node 
    --------------------
     
    (1 row)

citus_get_active_worker_nodes
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The citus_get_active_worker_nodes() function returns a list of active worker
host names and port numbers.

Arguments
************************

N/A

Return Value
******************************

List of tuples where each tuple contains the following information:

**node_name:** DNS name of the worker node

**node_port:** Port on the worker node on which the database server is listening

Example
***********************

.. code-block:: postgresql

    SELECT * from citus_get_active_worker_nodes();
     node_name | node_port 
    -----------+-----------
     localhost |      9700
     localhost |      9702
     localhost |      9701

    (3 rows)

.. _backend_pid:

citus_backend_gpid
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The citus_backend_gpid() function returns the global process identifier (GPID)
for the PostgreSQL backend serving the current session. A GPID encodes both a
node in the Citus cluster, and the operating system process ID of PostgreSQL on
that node.

Citus extends the PostgreSQL `server signaling functions
<https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL-TABLE)>`_
``pg_cancel_backend()`` and ``pg_terminate_backend()`` so that they accept
GPIDs. In Citus, calling these functions on one node can affect a backend
running on another node.

Arguments
************************

N/A

Return Value
******************************

An integer GPID, of the form (NodeId * 10,000,000,000) + ProcessId.

Example
***********************

.. code-block:: postgresql

    SELECT citus_backend_gpid();

::

     citus_backend_gpid
    --------------------
            10000002055


.. _check_cluster_node_health:

citus_check_cluster_node_health (beta)
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::

   This function is part of Citus 11-beta.

Check connectivity between all nodes. If there are N nodes, this function
checks all N\ :sup:`2` connections between them.

Arguments
************************

N/A

Return Value
******************************

List of tuples where each tuple contains the following information:

**from_nodename:** DNS name of the source worker node

**from_nodeport:** Port on the source worker node on which the database server is listening

**to_nodename:** DNS name of the destination worker node

**to_nodeport:** Port on the destination worker node on which the database server is listening

**result:** Whether a connection could be established

Example
***********************

.. code-block:: postgresql

    SELECT * FROM citus_check_cluster_node_health();

::

     from_nodename │ from_nodeport │ to_nodename │ to_nodeport │ result
    ---------------+---------------+-------------+-------------+--------
     localhost     |          1400 | localhost   |        1400 | t
     localhost     |          1400 | localhost   |        1401 | t
     localhost     |          1400 | localhost   |        1402 | t
     localhost     |          1401 | localhost   |        1400 | t
     localhost     |          1401 | localhost   |        1401 | t
     localhost     |          1401 | localhost   |        1402 | t
     localhost     |          1402 | localhost   |        1400 | t
     localhost     |          1402 | localhost   |        1401 | t
     localhost     |          1402 | localhost   |        1402 | t

    (9 rows)

.. _set_coordinator_host:

citus_set_coordinator_host
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

This function is required when adding worker nodes to a Citus cluster which was
created initially as a :ref:`single-node cluster <development>`. When the
coordinator registers a new worker, it adds a coordinator hostname from the
value of :ref:`local_hostname`, which is by default ``localhost``. The worker
would attempt to connect to ``localhost`` to talk to the coordinator, which is
obviously wrong.

Thus, the system administrator should call ``citus_set_coordinator_host``
before calling :ref:`citus_add_node` in a single-node cluster.

Arguments
************************

**host:** DNS name of the coordinator node.

**port:** (Optional) The port on which the coordinator lists for PostgreSQL
connections. Defaults to ``current_setting('port')``.

**node_role:** (Optional) Defaults to ``primary``.

**node_cluster:** (Optional) Defaults to ``default``.


Return Value
******************************

N/A

Example
*************************

.. code-block:: postgresql

   -- assuming we're in a single-node cluster

   -- first establish how workers should reach us
   SELECT citus_set_coordinator_host('coord.example.com', 5432);

   -- then add a worker
   SELECT * FROM citus_add_node('worker1.example.com', 5432);

master_get_table_metadata
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The master_get_table_metadata() function can be used to return distribution related metadata for a distributed table. This metadata includes the relation id, storage type, distribution method, distribution column, replication count (deprecated), maximum shard size and the shard placement policy for that table. Behind the covers, this function queries Citus metadata tables to get the required information and concatenates it into a tuple before returning it to the user.

Arguments
***********************

**table_name:** Name of the distributed table for which you want to fetch metadata.

Return Value
*********************************

A tuple containing the following information:

**logical_relid:** Oid of the distributed table. This values references the relfilenode column in the pg_class system catalog table.

**part_storage_type:** Type of storage used for the table. May be 't' (standard table), 'f' (foreign table) or 'c' (columnar table).

**part_method:** Distribution method used for the table. Must be 'h' (hash).

**part_key:** Distribution column for the table.

**part_replica_count:** (Deprecated) Current shard replication count.

**part_max_size:** Current maximum shard size in bytes.

**part_placement_policy:** Shard placement policy used for placing the table’s shards. May be 1 (local-node-first) or 2 (round-robin).

Example
*************************

The example below fetches and displays the table metadata for the github_events table.

.. code-block:: postgresql

    SELECT * from master_get_table_metadata('github_events');
     logical_relid | part_storage_type | part_method | part_key | part_replica_count | part_max_size | part_placement_policy 
    ---------------+-------------------+-------------+----------+--------------------+---------------+-----------------------
             24180 | t                 | h           | repo_id  |                  1 |    1073741824 |                     2
    (1 row)

.. _get_shard_id:

get_shard_id_for_distribution_column
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Citus assigns every row of a distributed table to a shard based on the value of the row's distribution column and the table's method of distribution. In most cases the precise mapping is a low-level detail that the database administrator can ignore. However, it can be useful to determine a row's shard, either for manual database maintenance tasks or just to satisfy curiosity. The :code:`get_shard_id_for_distribution_column` function provides this info for hash-distributed tables as well as reference tables.

Arguments
************************

**table_name:** The distributed table.

**distribution_value:** The value of the distribution column.

Return Value
******************************

The shard id Citus associates with the distribution column value for the given table.

Example
***********************

.. code-block:: postgresql

  SELECT get_shard_id_for_distribution_column('my_table', 4);

   get_shard_id_for_distribution_column
  --------------------------------------
                                 540007
  (1 row)

column_to_column_name
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Translates the :code:`partkey` column of :code:`pg_dist_partition` into a textual column name. This is useful to determine the distribution column of a distributed table.

For a more detailed discussion, see :ref:`finding_dist_col`.

Arguments
************************

**table_name:** The distributed table.

**column_var_text:** The value of :code:`partkey` in the :code:`pg_dist_partition` table.

Return Value
******************************

The name of :code:`table_name`'s distribution column.

Example
***********************

.. code-block:: postgresql

  -- get distribution column name for products table

  SELECT column_to_column_name(logicalrelid, partkey) AS dist_col_name
    FROM pg_dist_partition
   WHERE logicalrelid='products'::regclass;

Output:

::

  ┌───────────────┐
  │ dist_col_name │
  ├───────────────┤
  │ company_id    │
  └───────────────┘

citus_relation_size
$$$$$$$$$$$$$$$$$$$

Get the disk space used by all the shards of the specified distributed table. This includes the size of the "main fork," but excludes the visibility map and free space map for the shards.

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_relation_size('github_events'));

::

  pg_size_pretty
  --------------
  23 MB

citus_table_size
$$$$$$$$$$$$$$$$

Get the disk space used by all the shards of the specified distributed table, excluding indexes (but including TOAST, free space map, and visibility map).

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_table_size('github_events'));

::

  pg_size_pretty
  --------------
  37 MB

citus_total_relation_size
$$$$$$$$$$$$$$$$$$$$$$$$$

Get the total disk space used by the all the shards of the specified distributed table, including all indexes and TOAST data.

Arguments
*********

**logicalrelid:** the name of a distributed table.

Return Value
************

Size in bytes as a bigint.

Example
*******

.. code-block:: postgresql

  SELECT pg_size_pretty(citus_total_relation_size('github_events'));

::

  pg_size_pretty
  --------------
  73 MB


citus_stat_statements_reset
$$$$$$$$$$$$$$$$$$$$$$$$$$$

Removes all rows from :ref:`citus_stat_statements <citus_stat_statements>`. Note that this works independently from ``pg_stat_statements_reset()``. To reset all stats, call both functions.

Arguments
*********

N/A

Return Value
************

None

.. _cluster_management_functions:

Cluster Management And Repair Functions
----------------------------------------

citus_move_shard_placement
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

This function moves a given shard (and shards co-located with it) from one node to another. It is typically used indirectly during shard rebalancing rather than being called directly by a database administrator.

There are two ways to move the data: blocking or nonblocking. The blocking approach means that during the move all modifications to the shard are paused. The second way, which avoids blocking shard writes, relies on Postgres 10 logical replication.

After a successful move operation, shards in the source node get deleted. If the move fails at any point, this function throws an error and leaves the source and target nodes unchanged.

Arguments
**********

**shard_id:** Id of the shard to be moved.

**source_node_name:** DNS name of the node on which the healthy shard placement is present ("source" node).

**source_node_port:** The port on the source worker node on which the database server is listening.

**target_node_name:** DNS name of the node on which the invalid shard placement is present ("target" node).

**target_node_port:** The port on the target worker node on which the database server is listening.

**shard_transfer_mode:** (Optional) Specify the method of replication, whether to use PostgreSQL logical replication or a cross-worker COPY command. The possible values are:

  * ``auto``: Require replica identity if logical replication is possible, otherwise use legacy behaviour (e.g. for shard repair, PostgreSQL 9.6). This is the default value.
  * ``force_logical``: Use logical replication even if the table doesn't have a replica identity. Any concurrent update/delete statements to the table will fail during replication.
  * ``block_writes``: Use COPY (blocking writes) for tables lacking primary key or replica identity.

  .. note::

    Citus Community edition supports only the ``block_writes`` mode, and treats ``auto`` as ``block_writes``. Our :ref:`cloud_topic` is required for the more sophisticated modes.

Return Value
************

N/A

Example
********

.. code-block:: postgresql

    SELECT citus_move_shard_placement(12345, 'from_host', 5432, 'to_host', 5432);

.. _rebalance_table_shards:

rebalance_table_shards
$$$$$$$$$$$$$$$$$$$$$$$$$$$

The rebalance_table_shards() function moves shards of the given table to make
them evenly distributed among the workers. The function first calculates the
list of moves it needs to make in order to ensure that the cluster is balanced
within the given threshold. Then, it moves shard placements one by one from the
source node to the destination node and updates the corresponding shard
metadata to reflect the move.

Every shard is assigned a cost when determining whether shards are "evenly
distributed." By default each shard has the same cost (a value of 1), so
distributing to equalize the cost across workers is the same as equalizing the
number of shards on each. The constant cost strategy is called "by_shard_count"
and is the default rebalancing strategy.

The default strategy is appropriate under these circumstances:

1. The shards are roughly the same size
2. The shards get roughly the same amount of traffic
3. Worker nodes are all the same size/type
4. Shards haven't been pinned to particular workers

If any of these assumptions don't hold, then the default rebalancing can result
in a bad plan. In this case you may customize the strategy, using the
``rebalance_strategy`` parameter.

It's advisable to call :ref:`get_rebalance_table_shards_plan` before running
rebalance_table_shards, to see and verify the actions to be performed.

Arguments
**************************

**table_name:** (Optional) The name of the table whose shards need to be rebalanced. If NULL, then rebalance all existing colocation groups.

**threshold:** (Optional) A float number between 0.0 and 1.0 which indicates the maximum difference ratio of node utilization from average utilization. For example, specifying 0.1 will cause the shard rebalancer to attempt to balance all nodes to hold the same number of shards ±10%. Specifically, the shard rebalancer will try to converge utilization of all worker nodes to the (1 - threshold) * average_utilization ... (1 + threshold) * average_utilization range.

**max_shard_moves:** (Optional) The maximum number of shards to move.

**excluded_shard_list:** (Optional) Identifiers of shards which shouldn't be moved during the rebalance operation.

**shard_transfer_mode:** (Optional) Specify the method of replication, whether to use PostgreSQL logical replication or a cross-worker COPY command. The possible values are:

  * ``auto``: Require replica identity if logical replication is possible, otherwise use legacy behaviour (e.g. for shard repair, PostgreSQL 9.6). This is the default value.
  * ``force_logical``: Use logical replication even if the table doesn't have a replica identity. Any concurrent update/delete statements to the table will fail during replication.
  * ``block_writes``: Use COPY (blocking writes) for tables lacking primary key or replica identity.

  .. note::

    Citus Community edition supports only the ``block_writes`` mode, and treats ``auto`` as ``block_writes``. Our :ref:`cloud_topic` is required for the more sophisticated modes.

**drain_only:** (Optional) When true, move shards off worker nodes who have ``shouldhaveshards`` set to false in :ref:`pg_dist_node`; move no other shards.

**rebalance_strategy:** (Optional) the name of a strategy in :ref:`pg_dist_rebalance_strategy`. If this argument is omitted, the function chooses the default strategy, as indicated in the table.

Return Value
*********************************

N/A

Example
**************************

The example below will attempt to rebalance the shards of the github_events table within the default threshold.

.. code-block:: postgresql

	SELECT rebalance_table_shards('github_events');

This example usage will attempt to rebalance the github_events table without moving shards with id 1 and 2.

.. code-block:: postgresql

	SELECT rebalance_table_shards('github_events', excluded_shard_list:='{1,2}');

.. _get_rebalance_table_shards_plan:

get_rebalance_table_shards_plan
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Output the planned shard movements of :ref:`rebalance_table_shards` without
performing them. While it's unlikely, get_rebalance_table_shards_plan can
output a slightly different plan than what a rebalance_table_shards call with
the same arguments will do. This could happen because they are not executed at
the same time, so facts about the cluster -- e.g. disk space -- might differ
between the calls.

Arguments
**************************

The same arguments as rebalance_table_shards: relation, threshold,
max_shard_moves, excluded_shard_list, and drain_only. See documentation of that
function for the arguments' meaning.

Return Value
*********************************

Tuples containing these columns:

* **table_name**: The table whose shards would move
* **shardid**: The shard in question
* **shard_size**: Size in bytes
* **sourcename**: Hostname of the source node
* **sourceport**: Port of the source node
* **targetname**: Hostname of the destination node
* **targetport**: Port of the destination node

.. _get_rebalance_progress:

get_rebalance_progress
$$$$$$$$$$$$$$$$$$$$$$

Once a shard rebalance begins, the ``get_rebalance_progress()`` function lists the progress of every shard involved. It monitors the moves planned and executed by ``rebalance_table_shards()``.

Arguments
**************************

N/A

Return Value
*********************************

Tuples containing these columns:

* **sessionid**: Postgres PID of the rebalance monitor
* **table_name**: The table whose shards are moving
* **shardid**: The shard in question
* **shard_size**: Size of the shard in bytes
* **sourcename**: Hostname of the source node
* **sourceport**: Port of the source node
* **targetname**: Hostname of the destination node
* **targetport**: Port of the destination node
* **progress**: 0 = waiting to be moved; 1 = moving; 2 = complete
* **source_shard_size**: Size of the shard on the source node in bytes
* **target_shard_size**: Size of the shard on the target node in bytes

Example
**************************

.. code-block:: sql

  SELECT * FROM get_rebalance_progress();

::

  ┌───────────┬────────────┬─────────┬────────────┬───────────────┬────────────┬───────────────┬────────────┬──────────┬───────────────────┬───────────────────┐
  │ sessionid │ table_name │ shardid │ shard_size │  sourcename   │ sourceport │  targetname   │ targetport │ progress │ source_shard_size │ target_shard_size │
  ├───────────┼────────────┼─────────┼────────────┼───────────────┼────────────┼───────────────┼────────────┼──────────┼───────────────────┼───────────────────┤
  │      7083 │ foo        │  102008 │    1204224 │ n1.foobar.com │       5432 │ n4.foobar.com │       5432 │        0 │           1204224 │                 0 │
  │      7083 │ foo        │  102009 │    1802240 │ n1.foobar.com │       5432 │ n4.foobar.com │       5432 │        0 │           1802240 │                 0 │
  │      7083 │ foo        │  102018 │     614400 │ n2.foobar.com │       5432 │ n4.foobar.com │       5432 │        1 │            614400 │            354400 │
  │      7083 │ foo        │  102019 │       8192 │ n3.foobar.com │       5432 │ n4.foobar.com │       5432 │        2 │                 0 │              8192 │
  └───────────┴────────────┴─────────┴────────────┴───────────────┴────────────┴───────────────┴────────────┴──────────┴───────────────────┴───────────────────┘

.. _citus_add_rebalance_strategy:

citus_add_rebalance_strategy
$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Append a row to the ``pg_dist_rebalance_strategy``.

Arguments
**************************

For more about these arguments, see the corresponding column values in :ref:`pg_dist_rebalance_strategy`.

**name:** identifier for the new strategy

**shard_cost_function:** identifies the function used to determine the "cost" of each shard

**node_capacity_function:** identifies the function to measure node capacity

**shard_allowed_on_node_function:** identifies the function which determines which shards can be placed on which nodes

**default_threshold:** a floating point threshold that tunes how precisely the cumulative shard cost should be balanced between nodes

**minimum_threshold:** (Optional) a safeguard column that holds the minimum value allowed for the threshold argument of rebalance_table_shards(). Its default value is 0

Return Value
*********************************

N/A

.. _citus_set_default_rebalance_strategy:

citus_set_default_rebalance_strategy
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

Update the :ref:`pg_dist_rebalance_strategy` table, changing the strategy named
by its argument to be the default chosen when rebalancing shards.

Arguments
**************************

**name:** the name of the strategy in pg_dist_rebalance_strategy

Return Value
*********************************

N/A

Example
**************************

.. code-block:: postgresql

    SELECT citus_set_default_rebalance_strategy('by_disk_size');


.. _citus_remote_connection_stats:

citus_remote_connection_stats
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

The citus_remote_connection_stats() function shows the number of active
connections to each remote node.

Arguments
**************************

N/A

Example
**************************

.. code-block:: postgresql

  SELECT * from citus_remote_connection_stats();

::

  .
      hostname    | port | database_name | connection_count_to_node
  ----------------+------+---------------+--------------------------
   citus_worker_1 | 5432 | postgres      |                        3
  (1 row)

.. _citus_drain_node:

citus_drain_node
$$$$$$$$$$$$$$$$$$$$$$$$$$$

The citus_drain_node() function moves shards off the designated node and onto other nodes who have ``shouldhaveshards`` set to true in :ref:`pg_dist_node`. This function is designed to be called prior to removing a node from the cluster, i.e. turning the node's physical server off.

Arguments
**************************

**nodename:** The hostname name of the node to be drained.

**nodeport:** The port number of the node to be drained.

**shard_transfer_mode:** (Optional) Specify the method of replication, whether to use PostgreSQL logical replication or a cross-worker COPY command. The possible values are:

  * ``auto``: Require replica identity if logical replication is possible, otherwise use legacy behaviour (e.g. for shard repair, PostgreSQL 9.6). This is the default value.
  * ``force_logical``: Use logical replication even if the table doesn't have a replica identity. Any concurrent update/delete statements to the table will fail during replication.
  * ``block_writes``: Use COPY (blocking writes) for tables lacking primary key or replica identity.

  .. note::

    Citus Community edition supports only the ``block_writes`` mode, and treats ``auto`` as ``block_writes``. Our :ref:`cloud_topic` is required for the more sophisticated modes.

**rebalance_strategy:** (Optional) the name of a strategy in :ref:`pg_dist_rebalance_strategy`. If this argument is omitted, the function chooses the default strategy, as indicated in the table.

Return Value
*********************************

N/A

Example
**************************

Here are the typical steps to remove a single node (for example '10.0.0.1' on a standard PostgreSQL port):

1. Drain the node.

   .. code-block:: postgresql

     SELECT * from citus_drain_node('10.0.0.1', 5432);

2. Wait until the command finishes
3. Remove the node

When draining multiple nodes it's recommended to use :ref:`rebalance_table_shards` instead. Doing so allows Citus to plan ahead and move shards the minimum number of times.

1. Run this for each node that you want to remove:

   .. code-block:: postgresql

     SELECT * FROM citus_set_node_property(node_hostname, node_port, 'shouldhaveshards', false);

2. Drain them all at once with :ref:`rebalance_table_shards`:

   .. code-block:: postgresql

     SELECT * FROM rebalance_table_shards(drain_only := true);

3. Wait until the draining rebalance finishes
4. Remove the nodes

.. _isolate_tenant_to_new_shard:

isolate_tenant_to_new_shard
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

.. note::
  The isolate_tenant_to_new_shard function is a part of our :ref:`cloud_topic` only.

This function creates a new shard to hold rows with a specific single value in the distribution column. It is especially handy for the multi-tenant Citus use case, where a large tenant can be placed alone on its own shard and ultimately its own physical node.

For a more in-depth discussion, see :ref:`tenant_isolation`.

Arguments
*************************

**table_name:** The name of the table to get a new shard.

**tenant_id:** The value of the distribution column which will be assigned to the new shard.

**cascade_option:** (Optional) When set to "CASCADE," also isolates a shard from all tables in the current table's :ref:`colocation_groups`.

Return Value
***************************

**shard_id:** The function returns the unique id assigned to the newly created shard.

Examples
**************************

Create a new shard to hold the lineitems for tenant 135:

.. code-block:: postgresql

  SELECT isolate_tenant_to_new_shard('lineitem', 135);

::

  ┌─────────────────────────────┐
  │ isolate_tenant_to_new_shard │
  ├─────────────────────────────┤
  │                      102240 │
  └─────────────────────────────┘

citus_create_restore_point
$$$$$$$$$$$$$$$$$$$$$$$$$$

Temporarily blocks writes to the cluster, and creates a named restore point on all nodes. This function is similar to `pg_create_restore_point <https://www.postgresql.org/docs/current/static/functions-admin.html#FUNCTIONS-ADMIN-BACKUP>`_, but applies to all nodes and makes sure the restore point is consistent across them. This function is well suited to doing point-in-time recovery, and cluster forking.

Arguments
*************************

**name:** The name of the restore point to create.

Return Value
***************************

**coordinator_lsn:** Log sequence number of the restore point in the coordinator node WAL.

Examples
**************************

.. code-block:: postgresql

  select citus_create_restore_point('foo');

::

  ┌────────────────────────────┐
  │ citus_create_restore_point │
  ├────────────────────────────┤
  │ 0/1EA2808                  │
  └────────────────────────────┘
