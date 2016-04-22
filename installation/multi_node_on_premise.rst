.. _multi_node_on_premise:

Multi-node setup on-premise
================================================================================

At a high level, the multi-node setup involves two steps that differ from those of a single node cluster. First, you need to either manually log in to all the nodes and issue the installation and configuration commands, or rely on tools such as `pssh <http://code.google.com/p/parallel-ssh/>`_ to run the remote commands in parallel for you. Second, you need to configure authentication settings on the nodes to allow for them to talk to each other.

In the following tutorials, we assume that you will manually log in to all the nodes and issue commands. We also assume that the worker nodes have DNS names worker-101, worker-102 and so on. Lastly, we note that you can edit the hosts file in /etc/hosts if your nodes don't already have their DNS names assigned.

You can choose the appropirate tutorial below depending on whether your operating system
supports .rpm packages or .deb packages.

:ref:`multi_node_rpm`

:ref:`multi_node_deb`

.. toctree::
   :hidden:

   multi_node_rpm.rst
   multi_node_deb.rst
