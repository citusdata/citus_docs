:orphan:

.. _cloud_topic:

Citus Cloud
###########

.. NOTE::
   We are no longer onboarding new users to Citus Cloud on AWS. The good news is, Citus is still available to you: as open source, as on-prem enterprise software, and in the cloud on Microsoft Azure, as a fully-integrated deployment option in Azure Database for PostgreSQL.

Citus Cloud is a fully managed hosted version of Citus Enterprise edition on top of AWS. It goes way beyond the functionality of the Citus extension itself. Cloud does failovers in a way that’s transparent to the application, elastically scales up and scales out, takes automatic backups for disaster recovery, has monitoring and alarms built in, and provides patches and upgrades with no downtime. We also offer a managed deployment on `Azure Database for PostgreSQL — Hyperscale (Citus) <https://docs.microsoft.com/azure/postgresql/>`_.

* First you'll want to get an account and :ref:`Provision <cloud_overview>` a database.
* Once a Cloud database is provisioned, read :ref:`connection`  to connect your application and REPL to it.
* Next see how easy it is to :ref:`scale <cloud_scaling>` the database -- both up (bigger hardware) and out (more nodes).
* Citus Cloud has an interesting "time travel" feature called :ref:`cloud_forking`. It'll definitely give you some ideas of new ways to use the database.

When you're comfortable with the topics so far, try diving into the :ref:`reference_topic`.
