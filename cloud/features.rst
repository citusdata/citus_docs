Features
########

Replication model
-----------------

Citus Cloud runs with a different replication from outlined in Citus docs. Instead of using Citus replication we leverage Postgres streaming replication. Postgres streaming replication provides superior gurantees about the state of your data, and with years of experience managing it we take the hard work out of it for you. With Citus Cloud if you want the equivilent of replication_factor equal to 2, the most popular setting for Citus users then you simply enable HA at provisioning.

Continuous protection
---------------------

Continuous protection is provided on all Citus Cloud clusters. To provide this we perform backups of your data every 24 hours, then stream the write-ahead-log (WAL) from Postgres to S3 every 16 MB or 60 seconds, whichever is less. This means in the event of a full hardware failure, even if you don't have high availability enabled, you won't lose any data. In the event of a complete infrastructure failure we'll restore your back-up and replace the WAL to the exact moment before your system crashed. 

High Availability
-----------------

In addition to continuous protection which is explained above. High availability is available if your application requires less exposure to downtime. If at provisioning you select high availability we provision stand-bys. This can be for your primary node, or for your distributed nodes. 

