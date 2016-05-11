.. _range_distribution:

Range Distribution (Manual)
############################

Citus also supports range based distribution, but this currently requires manual effort to set up. In this section, we briefly describe how you can set up range distribution and where it can be useful.

.. note::
    The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example:
    
    ::
        
        export PATH=/usr/lib/postgresql/9.5/:$PATH

To create a range distributed table, you need to first define the table schema. To do so, you can define a table using the `CREATE TABLE <http://www.postgresql.org/docs/9.5/static/sql-createtable.html>`_ statement in the same way as you would do with a regular postgresql table.

::

    psql -h localhost -d postgres
    CREATE TABLE github_events
    (
    	event_id bigint,
    	event_type text,
    	event_public boolean,
    	repo_id bigint,
    	payload jsonb,
    	repo jsonb,
    	actor jsonb,
    	org jsonb,
    	created_at timestamp
    );

Next, you can use the master_create_distributed_table() function to mark the table as a range distributed table and specify its distribution column.

::

    SELECT master_create_distributed_table('github_events', 'repo_id', 'range');

This function informs Citus that the github_events table should be distributed by range on the repo_id column.

Range distribution signifies to the database that all the shards have non-overlapping ranges of the distribution key. Currently, the \copy command for data loading does not impose that the shards have non-overlapping distribution key ranges. Hence, the user needs to make sure that the shards don't overlap.

To set up range distributed shards, you first have to sort the data on the distribution column. This may not be required if the data already comes sorted on the distribution column (eg. facts, events, or time-series tables distributed on time). The next step is to split the input file into different files having non-overlapping ranges of the distribution key and run the \copy command for each file separately. As \copy always creates a new shard, the shards are guaranteed to have non-overlapping ranges.

As an example, we'll describe how to copy data into the github_events table shown above. First, you download and extract two hours of github data.

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-0.csv.gz
    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-1.csv.gz
    gzip -d github_events-2015-01-01-0.csv.gz
    gzip -d github_events-2015-01-01-1.csv.gz

Then, you merge both files into a single file by using the cat command.

::

    cat github_events-2015-01-01-0.csv github_events-2015-01-01-1.csv > github_events-2015-01-01-0-1.csv

Next, you should sort the data on the repo_id column using the linux sort command.

::

    sort -n --field-separator=',' --key=4 github_events-2015-01-01-0-1.csv > github_events_sorted.csv

Finally, you can split the input data such that no two files have any overlapping partition column ranges. This can be done by writing a custom script or manually ensuring that files don’t have overlapping ranges of the repo_id column.

For this example, you can download and extract data that has been previously split on the basis of repo_id.

::

    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range1.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range2.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range3.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range4.csv.gz
    gzip -d github_events_2015-01-01-0-1_range1.csv.gz
    gzip -d github_events_2015-01-01-0-1_range2.csv.gz
    gzip -d github_events_2015-01-01-0-1_range3.csv.gz
    gzip -d github_events_2015-01-01-0-1_range4.csv.gz

Then, you can connect to the master using psql and load the files using the \copy command.

::

    psql -h localhost -d postgres
    SET citus.shard_replication_factor TO 1;
    \copy github_events from 'github_events_2015-01-01-0-1_range1.csv' with csv;
    \copy github_events from 'github_events_2015-01-01-0-1_range2.csv' with csv;
    \copy github_events from 'github_events_2015-01-01-0-1_range3.csv' with csv;
    \copy github_events from 'github_events_2015-01-01-0-1_range4.csv' with csv;

After this point, you can run queries on the range distributed table. To generate per-repository metrics, your queries would generally have filters on the repo_id column. Then, Citus can easily prune away unrelated shards and ensure that the query hits only one shard. Also, groupings and orderings on repo_id can be easily pushed down the workers leading to more efficient queries. We also note here that all the commands which can be run on tables using the append distribution method can be run on tables using range distribution. This includes \copy, the append and shard creation UDFs and the delete UDF. 

The difference between range and append methods is that Citus’s distributed query planner has extra knowledge that the shards have distinct non-overlapping distribution key ranges. This allows the planner to push down more operations to the workers so that they can be executed in parallel. This reduces both the amount of data transferred across network and the amount of computation to be done for aggregation on the master.
