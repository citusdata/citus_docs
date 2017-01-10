Features
########

Replication model
-----------------

Citus Cloud runs with a different replication from that outlined in the Citus docs. We leverage PostgreSQL streaming replication rather than Citus replication. This provides superior guarantees about data preservation. Enable HA at provisioning to achieve the equivalent of Citus with replication_factor set to two (the most popular setting for Citus users).

Continuous protection
---------------------

Citus Cloud continuously protects the cluster data against hardware failure. To do this we perform backups every twenty-four hours, then stream the write-ahead log (WAL) from PostgreSQL to S3 every 16 MB or 60 seconds, whichever is less. Even without high availability enabled you won't lose any data. In the event of a complete infrastructure failure we'll restore your back-up and replay the WAL to the exact moment before your system crashed.

High Availability
-----------------

In addition to continuous protection which is explained above, high availability is available if your application requires less exposure to downtime. We provision stand-bys if you select high availability at provisioning time. This can be for your primary node, or for your distributed nodes.

Security
--------

Encryption
~~~~~~~~~~

All data within Citus Cloud is encrypted at rest, including data on the instance as well as all backups for disaster recovery. We also require that you connect to your database with TLS.

Two-Factor Authentication
~~~~~~~~~~~~~~~~~~~~~~~~~

We support two factor authentication for all Citus accounts. You can enable it from within your Citus Cloud account. We support Google Authenticator and Authy as two primary apps for setting up your two factor authentication.


.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'features', section: 'cloud'});
  </script>
