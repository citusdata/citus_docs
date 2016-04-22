.. _hash_updating_and_deleting_data:

Updating and Deleting Data
##########################



You can also update / delete rows from your tables, using the standard PostgreSQL `UPDATE <http://www.postgresql.org/docs/9.4/static/sql-update.html>`_ / `DELETE <http://www.postgresql.org/docs/9.4/static/sql-delete.html>`_ commands.

::

    UPDATE github_events SET org = NULL WHERE repo_id = 5152285;
    DELETE FROM github_events WHERE repo_id = 5152285;

Currently, we require that an UPDATE or DELETE involves exactly one shard. This means commands must include a WHERE qualification on the distribution column that restricts the query to a single shard. Such qualifications usually take the form of an equality clause on the table’s distribution column.
