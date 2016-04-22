.. _data_warehousing_queries:

Data Warehousing Queries
########################

We know we have more to do before we can declare CitusDB complete. Still, we have a version which works well for real-time analytics and that many companies rely on in production today. We are continuously working to increase SQL coverage to better support data warehousing use-cases. In the mean-time, since CitusDB is based on PostgreSQL, we can usually offer workarounds that work well for a number of use cases. So if you can't find documentation for a SQL feature or run into an unsupported feature, please send us an email at engage@citusdata.com.

Here, we would like to illustrate one such example which works well when queries have restrictive filters i.e. when very few results need to be transferred to the master node. In such cases, it is possible to run data warehousing queries in two steps by storing the results of the inner queries in regular PostgreSQL tables on the master node. Then, the next step can be executed on the master node like a regular PostgreSQL query.

For example, currently CitusDB does not have out of the box support for window functions. Suppose you have a query on the github_events table that has a window function like the following:


::

    SELECT
        repo_id, actor->'id', count(*)
    OVER
        (PARTITION BY repo_id)
    FROM
        github_events
    WHERE
        repo_id = 1 OR repo_id = 2;

We can re-write the query like below:

Statement 1:

::

    CREATE TEMP TABLE results AS 
    (SELECT
        repo_id, actor->'id' as actor_id
    FROM
        github_events
    WHERE
    	repo_id = 1 OR repo_id = 2
    );

Statement 2:

::

    SELECT
        repo_id, actor_id, count(*)
    OVER
        (PARTITION BY repo_id)
    FROM
        results;

Similar workarounds can be found for other data warehousing queries involving complex subqueries or outer joins.

Note: The above query is a simple example intended at showing how meaningful workarounds exist around the lack of support for a few query types. Over time, we intend to support these commands out of the box within the database.
