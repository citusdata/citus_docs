.. distributing_by_identifier.rst

Distributing by Identifier (Real-time Data Loading)
##########################################################

This data model is more suited to cases where users want to do real-time inserts
along with analytics on their data or want to distribute by a non-ordered
column. In this case, CitusDB will maintain hash token ranges for all the
created shards. Whenever a row is inserted, updated or deleted, CitusDB (with
the help of pg_shard) will redirect the query to the correct shard and issue it
locally.

Since, users generally want to generate per-repo statistics, we distribute their data
by hash on the repo_id column. Then, CitusDB can easily prune away the unrelated
shards and speed up the queries with a filter on the repo id.

As in the previous case, users can choose to store their raw events data in
CitusDB or aggregate their data on the desired time interval.


.. toctree::
   :hidden:

   id_querying_raw_data.rst
   id_querying_aggregated_data.rst
