.. _citusdb_sql_reference:

CitusDB SQL Language Reference
###############################


CitusDB uses SQL as its query language. As CitusDB provides distributed functionality by extending PostgreSQL, it is compatible with all PostgreSQL constructs. This means that users can use all the tools and features that come with the rich and extensible PostgreSQL ecosystem. These features include but are not limited to :-

* support for wide range of `data types <http://www.postgresql.org/docs/9.4/static/datatype.html>`_ (including support for semi-structured data types like `jsonb <http://www.postgresql.org/docs/9.4/static/datatype-json.html>`_, `hstore <http://www.postgresql.org/docs/9.4/static/hstore.html>`_)

* `full text search <http://www.postgresql.org/docs/9.4/static/textsearch.html>`_

* `operators and functions <http://www.postgresql.org/docs/9.4/static/functions.html>`_

* `foreign data wrappers <https://wiki.postgresql.org/wiki/Foreign_data_wrappers>`_

* `extensions <http://pgxn.org>`_

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL 9.4 documentation <http://www.postgresql.org/docs/9.4/static/index.html>`_.

To learn about the new features in PostgreSQL 9.4 on which the current CitusDB version is based, you can see the `PostgreSQL 9.4 release notes <http://www.postgresql.org/docs/9.4/static/release.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by CitusDB users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/9.4/static/sql-commands.html>`_. 

Note: PostgreSQL has a wide SQL coverage and CitusDB may not support the entire SQL spectrum out of the box. We aim to continuously improve the SQL coverage of CitusDB in the upcoming releases. In the mean time, if you have an advanced use case which requires support for these constructs, please get in touch with us by dropping a note to engage@citusdata.com.
