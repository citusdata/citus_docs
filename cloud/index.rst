Citus Overview
==============

Citus Cloud is a fully managed hosted version of Citus Enterprise edition on top of AWS. Citus Cloud comes with the benefit of Citus allowing you to easily scale out your memory and processing power, without having to worry about keeping it up and running.

Provisioning
############

Once you've created your account at https://console.citusdata.com you can provision your Citus cluster. When you login you'll be at the home of the dashboard, and from here you can click New Formation to begin your formation creation.

.. image:: ../images/cloud_provisioning.png

Pre-configured plans
--------------------

To make it simpler for you to get up and running we've preconfigured a number of Citus Cloud plans. All Citus plans come with:

1. A primary instance which you will connect to and is suitable for storing your smaller tables (under 1 million rows) on.
2. A set of distributed nodes which your distributed tables will be sharded across
3. High availability, meaning we will be running standbys should you need to fail over. 

If you do not need high availability or want a different number or size of nodes than you see available you can create your own custom plan. 

Custom plans
------------

Each custom plan allows you to configure the size of your primary instance, the number and size of distributed nodes, and whether the primary instance and nodes have HA enabled. Discounts are available for longer-term commitments on custom plans which make them comparable in price to the preconfigured plans.


Sizing your Citus Cluster
-------------------------

All nodes within a Citus cluster come with 512 GB of storage. The number of nodes and size of the nodes you need will vary based on your data volume and performance requirements. We encourage you to focus on the number of logical shards and right distribution key first before focusing on overall size of your cluster. 

Citus will use only as many physical cores to process a query as there are logical shards in your cluster. Thus we recommend creating sufficient shards to give your cluster room to grow. A good estimate is 4-8x the number of cores you currently use in your cluster. For instance choosing 128 logical shards is quite reasonable when you create your distributed tables.
