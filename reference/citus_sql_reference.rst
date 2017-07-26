.. _citus_sql_reference:

Citus SQL Language Reference
###############################

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus. These features include but are not limited to :-

* support for wide range of `data types <http://www.postgresql.org/docs/current/static/datatype.html>`_ (including support for semi-structured data types like `jsonb <http://www.postgresql.org/docs/current/static/datatype-json.html>`_, `hstore <http://www.postgresql.org/docs/current/static/hstore.html>`_)

* `full text search <http://www.postgresql.org/docs/current/static/textsearch.html>`_

* `operators and functions <http://www.postgresql.org/docs/current/static/functions.html>`_

* `foreign data wrappers <https://wiki.postgresql.org/wiki/Foreign_data_wrappers>`_

* `extensions <http://pgxn.org>`_

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_. 

.. note::
  PostgreSQL has a wide SQL coverage and Citus may not support the entire SQL spectrum out of the box for distributed tables. We aim to continuously improve Citus's SQL coverage in the upcoming releases. In the mean time, if you have a use case which requires support for these constructs, please `get in touch with us <https://www.citusdata.com/about/contact_us>`_.
