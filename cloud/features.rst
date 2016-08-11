Features
########

Replication model
-----------------

Citus Cloud runs with a different replication from that outlined in the Citus docs. We leverage PostgreSQL streaming replication rather than Citus replication. This provides superior guarantees about data preservation. Enable HA at provisioning to achieve the equivalent of Citus with replication_factor set to two (the most popular setting for Citus users).

Continuous protection
---------------------

Citus Cloud continuously protects cluster data against hardware failure. To do this we perform backups of your data every 24 hours, then stream the write-ahead log (WAL) from Postgres to S3 every 16 MB or 60 seconds, whichever is less. Even without high availability enabled you won't lose any data. In the event of a complete infrastructure failure we'll restore your back-up and replace the WAL to the exact moment before your system crashed.

High Availability
-----------------

In addition to continuous protection which is explained above, high availability is available if your application requires less exposure to downtime. If at provisioning you select high availability we provision stand-bys. This can be for your primary node, or for your distributed nodes.

.. raw:: html

  <script type="text/javascript">
  Intercom('trackEvent', 'docs-cloud-pageview');
  </script>