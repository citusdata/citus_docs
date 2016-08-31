Citus Overview
==============

Citus Cloud is a fully managed hosted version of Citus Enterprise edition on top of AWS. Citus Cloud comes with the benefit of Citus allowing you to easily scale out your memory and processing power, without having to worry about keeping it up and running.

Provisioning
############

Once you've created your account at `https://console.citusdata.com <https://console.citusdata.com>`_ you can provision your Citus cluster. When you login you'll be at the home of the dashboard, and from here you can click New Formation to begin your formation creation. 

.. image:: ../images/cloud_provisioning.png

Configuring your plan
---------------------

Citus Cloud plans can vary based on the size of your primary node, size of your distributed nodes, how many distributed nodes and whether you have high availability or not. From within the Citus console you can configure you plan or you can preview what it might look like within the `pricing calculator <https://console.citusdata.com>`_. 

The key items you'll care about for each node:

- Storage - All nodes come with 512 GB of storage
- Memory - The memory on each node varies based on the size of node you select
- Cores - The cores on each node varies based on the size of node you select

High Availability
~~~~~~~~~~~~~~~~~

By enabling high availability for your cluster we automatically provision stand-bys. These stand-bys receive streaming updates directly from each of the leader nodes. We continuously monitor the leader nodes to ensure they're available and healthy, in the event of a failure we automatically fail you over. 

If you're application needs higher uptime requirements high availability will provide more uptime. Both with and without high availability enabled your data is replicated to S3 so disaster recovery is possible–reducing any risk of data loss. While we do not offer a SLA on uptime; The rough guideline we encourage is that: if an issues occurs and your instance fails and you cannot suffer up to 1 hr of downtime then high availability is encouraged.


Custom plans
.. raw:: html

  <script type="text/javascript">
  Intercom('trackEvent', 'docs-cloud-pageview');
  </script>
