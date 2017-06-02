Scaling
#######

Citus Cloud provides self-service scaling to deal with increased load. The web interface makes it easy to either add new worker nodes or increase existing nodes' memory capacity.

For most cases either approach to scaling is fine and will improve performance. However there are times you may want to choose one over the other. If the cluster is reaching its disk limit then adding more nodes is the best choice. Alternately, if there is still a lot of headroom on disk but performance is suffering, then scaling node RAM is the way to go.

Both adjustments are available in the formation configuration panel of the settings tab:

.. image:: ../images/cloud-formation-configuration.png

Clicking the node change link provides two sliders:

.. image:: ../images/cloud-nodes-slider.png

The first slider, **count**, scales out the cluster by adding new nodes. The second, **RAM**, scales it up by changing the amount of RAM on existing nodes.

After you adjust the sliders and accept the changes, Citus Cloud begins applying the changes subject to the user-specified maintenance window:

.. image:: ../images/cloud-maintenance-window.png

Scaling Up (increasing node size)
---------------------------------

Resizing node RAM works by creating a PostgreSQL follower for each node, where the followers are provisioned with the desired amount of RAM. It takes an average of forty minutes per hundred gigabytes of data for the primary nodes' data to be fully synchronized on the followers. After the synchronization is complete, Citus Cloud does a quick failover from the existing primary nodes to their followers which takes about one minute. The creation and switchover process uses the same well-tested replication mechanism that powers Cloud's :ref:`ha` feature.

Scaling Out (adding new nodes)
------------------------------

Node addition completes in five to ten minutes, which is faster than node resizing because the new nodes are created without data. To take advantage of the new nodes you still must adjust manually rebalance the shards, meaning move some shards from existing nodes to the new ones. Citus does not automatically do this on node creation because shard rebalancing takes locks that prevent inserts. The choice of when to run the shard rebalancer is left to the database administrator.

To start the shard rebalance, connect to the cluster coordinator node with psql and run:

.. code-block:: postgres

  SELECT rebalance_table_shards('distributed_table_name');

Citus will output the progress as it moves each shard.

.. note::

  The :code:`rebalance_table_shards` function rebalances all tables in the :ref:`colocation group <colocation_groups>` of the table named in its argument. Thus you do not have to call it for every single table, just call it on a representative table from each colocation group.
