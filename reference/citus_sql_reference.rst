.. _citus_sql_reference:

Citus SQL Language Reference
###############################

As Citus provides distributed functionality by extending PostgreSQL, it is compatible with PostgreSQL constructs. This means that users can use the tools and features that come with the rich and extensible PostgreSQL ecosystem for distributed tables created with Citus.

Citus supports all SQL queries on distributed tables, with only these exceptions:

* Correlated subqueries
* `Recursive <https://www.postgresql.org/docs/current/static/queries-with.html#idm46428713247840>`_/`modifying <https://www.postgresql.org/docs/current/static/queries-with.html#QUERIES-WITH-MODIFYING>`_ CTEs
* `TABLESAMPLE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FROM>`_
* `SELECT … FOR UPDATE <https://www.postgresql.org/docs/current/static/sql-select.html#SQL-FOR-UPDATE-SHARE>`_
* `Grouping sets <https://www.postgresql.org/docs/current/static/queries-table-expressions.html#QUERIES-GROUPING-SETS>`_

Furthermore, in :ref:`mt_use_case` when queries are filtered by table :ref:`dist_column` to a single tenant then all SQL features work, including the ones above.

To learn more about PostgreSQL and its features, you can visit the `PostgreSQL documentation <http://www.postgresql.org/docs/current/static/index.html>`_.

For a detailed reference of the PostgreSQL SQL command dialect (which can be used as is by Citus users), you can see the `SQL Command Reference <http://www.postgresql.org/docs/current/static/sql-commands.html>`_.
