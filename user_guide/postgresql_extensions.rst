.. _postgresql_extensions:

PostgreSQL extensions
######################

As CitusDB is based on PostgreSQL and each node in a CitusDB cluster is a nearly vanilla PostgreSQL (9.4), you can directly use Postgresql extensions such as hstore, hll, or PostGIS with CitusDB. The only difference is that you would need to run the create extension command on both the master and the worker nodes before starting to use it.

Note: Sometimes, there might be a few features of the extension that may not be supported out of the box. For example, a few aggregates in an extension may need to be modified a bit to be parallelized across multiple nodes. Please contact us at engage@citusdata.com if some feature from your favourite extension does not work as expected with CitusDB.

With this, we conclude our discussion around the usage of CitusDB. To learn more about the commands, UDFs or configuration parameters, you can visit the :ref:`reference_index` section of our documentation. To continue learning more about CitusDB and its features, including database internals and cluster administration, you can visit our :ref:`admin_guide_index`. If you cannot find documentation about a feature you are looking for, please contact us at engage@citusdata.com.
