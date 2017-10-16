Privacy
=======

At Citus Data we know you trust our product to manage sensitive information. We take your privacy seriously, and want to be transparent about what information we collect.

In order to monitor the usage of Citus across operating systems and data workload, each installation sends back anonymous statistics to our servers. You are able to opt out of this data collection.

What we Collect
---------------

Reporting happens on installation and every twenty-four hours thereafter. Here is what happens:

* Citus checks if there is a newer version of itself, and if so emits a notice to the database logs.
* Citus collects and sends these statistics about your cluster:
   * Randomly generated cluster identifier
   * Number of servers
   * OS and version (output of ``uname -psr`` command)
   * Number of tables, rounded to a power of two
   * Total size of shards, rounded to a power of two

How to Opt Out
--------------

If you wish to disable our anonymized cluster statistics gathering, set the following GUC in postgresql.conf on your coordinator node:

.. code-block:: ini

  citus.enable_statistics_collection = off

If you have super-user SQL access you can also achieve this without needing to find and edit the configuration file. Just execute the following statement in psql:

.. code-block:: postgresql

  ALTER SYSTEM SET citus.enable_statistics_collection = 'off';
