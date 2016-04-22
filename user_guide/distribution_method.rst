.. _distribution_method:

Distribution Method
###################

The next step after choosing the right distribution column is deciding the right distribution method. CitusDB supports two distribution methods: append and hash. CitusDB also provides the option for range distribution but that currently requires manual effort to set up.

As the name suggests, append based distribution is more suited to append-only use cases. This typically includes event based data which arrives in a time-ordered series. Users then distribute their largest tables by time, and batch load their events into CitusDB in intervals of N minutes. This data model can be generalized to a number of time series use cases; for example, each line in a website's log file, machine activity logs or aggregated website events. Append based distribution supports more efficient range queries. This is because given a range query on the distribution key, the CitusDB query planner can easily determine which shards overlap that range and send the query to only to relevant shards.

Hash based distribution is more suited to cases where users want to do real-time inserts along with analytics on their data or want to distribute by a non-ordered column (eg. user id). This data model is relevant for real-time analytics use cases; for example, actions in a mobile application, user website events, or social media analytics. In this case, CitusDB will maintain minimum and maximum hash ranges for all the created shards. Whenever a row is inserted, updated or deleted, CitusDB will redirect the query to the correct shard and issue it locally. This data model is more suited for doing co-located joins and for queries involving equality based filters on the distribution column.

CitusDB uses different syntaxes for creation and manipulation of append and hash distributed tables. Also, the operations / commands supported on the tables differ based on the distribution method chosen. In the sections below, we describe the syntax for creating append and hash distributed tables, and also describe the operations which can be done on them. We also briefly discuss how users can setup range partitioning manually.


