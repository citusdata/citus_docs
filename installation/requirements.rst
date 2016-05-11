.. _requirements:

Requirements
############

Citus works with modern 64-bit Linux and most Unix based operating systems. Citus 5.1 offically supports PostgreSQL 9.5 and later versions. The extension will also work against PostgreSQL 9.4 but versions older than 9.4 are not supported.

Before setting up a Citus cluster, you should ensure that the network and firewall settings are configured to allow:

* The database clients (eg. psql, JDBC / OBDC drivers) to connect to the master.        
* All the nodes in the cluster to connect to each other over TCP without any interactive authentication.
