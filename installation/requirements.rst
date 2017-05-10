.. _requirements:

Requirements
############

Citus works with modern 64-bit Linux and most Unix based operating systems. Citus 6.0 requires PostgreSQL 9.5 or later versions.

Before setting up a Citus cluster, you should ensure that the network and firewall settings are configured to allow:

* The database clients (eg. psql, JDBC / OBDC drivers) to connect to the coordinator.
* All the nodes in the cluster to connect to each other over TCP without any interactive authentication.
