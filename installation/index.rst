.. _installation_index:

Installation Guide
##################

This section provides instructions on installing and configuring CitusDB. There are two possible setups for CitusDB; namely single-node and multi-node cluster. Note that both the clusters execute the exact same logic i.e. they both run independent master and worker databases that communicate over the `PostgreSQL communication libraries (libpq) <http://www.postgresql.org/docs/9.4/static/libpq.html>`_. They primarily differ in that the single node cluster is bound by the node's hardware resources while the multi-node cluster requires setting up authentication between the different nodes.

The single-node installation is a quick way to setup a test CitusDB cluster. However, a single node cluster can quickly get bottlenecked on hardware resources. We therefore recommend setting up a multi-node cluster for performance testing and production use cases. For setting up multi-node clusters on AWS easily, we recommend using the :ref:`CloudFormation template<multi_node_aws>`.

Before diving into the exact setup instructions, we first describe the OS requirements for running CitusDB.

Supported Operating Systems
***************************

In general, any modern 64-bit Linux based operating system should be able to install and run CitusDB. Below is the list of platforms that have received specific testing at the time of release:

* Amazon Linux
* Redhat / Centos 6+
* Fedora 19+
* Ubuntu 10.04+
* Debian 6+

Note: The above is not an exhaustive list and only includes platforms where CitusDB packages are extensively tested. If your operating system is supported by PostgreSQL and you'd like to use CitusDB, please get in touch with us at engage@citusdata.com.

Single Node Cluster
*******************

The tutorials below provide instructions for installing and setting up a single node CitusDB cluster on various Linux systems.
These instructions differ slightly depending on whether your operating system supports .rpm packages or .deb packages.

Note: Single node installations are recommended only for test clusters. Please use multi-node clusters for production deployments.

:ref:`single_node_rpm`

:ref:`single_node_deb`

.. toctree::
   :hidden:

   single_node_rpm.rst
   single_node_deb.rst

Multi Node Cluster
********************************************************************************

The tutorials below provide instructions to install and setup a multi-node CitusDB cluster. You can either setup the cluster on AWS using our CloudFormation templates or install CitusDB on premise on your machines. We recommend using the CloudFormation templates for cloud deployments as it quickly sets up a fully operational CitusDB cluster.

:ref:`multi_node_aws`

:ref:`multi_node_on_premise`


.. toctree::
   :hidden:

   multi_node_aws.rst
   multi_node_on_premise.rst
