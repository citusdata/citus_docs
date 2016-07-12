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

Each custom plans allows you to configure the size of your primary instance and whether it has HA or not, the number of distributed nodes, size of them, and whether they have HA or not. With longer term commitements discounts are available on custom plans which are already baked into some of the preconfigured plans. 


Sizing your Citus Cluster
-------------------------

All nodes within a Citus cluster come with 512 GB of storage. The number of nodes and size of the nodes you need will vary based on your data volume and performance requirements. We encourange you to focus on the number of logical shards and right distribution key first before focusing on overall size of your cluster. 

For the number of right logical shards we recommend setting it to the number of physical cores you expect to grow to at some point. A good estimate is 4-8x the number of cores you're currently using within your cluster. A good starting point can often be around 128 logical shards when you create your distributed tables.