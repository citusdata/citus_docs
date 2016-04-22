.. _range_distribution:

Range Distribution (Manual)
############################

CitusDB also supports range based distribution, but this currently requires manual effort to set up. In this section, we briefly describe how one can set up range distribution and where it can be useful.

The syntax for creating a table using range distribution is very similar to a table using append distribution i.e. with the DISTRIBUTE BY clause.

::

    /opt/citusdb/4.0/bin/psql -h localhost -d postgres
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
    ) DISTRIBUTE BY RANGE (repo_id);

Range distribution signifies to the database that all the shards have non-overlapping ranges of the distribution key. Currently, the \stage command for data loading does not impose that the shards have non-overlapping distribution key ranges. Hence, the user needs to make sure that the shards don't overlap.

To set up range distributed shards, you first have to sort the data on the distribution column. This may not be required if the data already comes sorted on the distribution column (eg. facts, events, or time-series tables distributed on time). The next step is to split the input file into different files having non-overlapping ranges of the distribution key and run the \stage command for each file separately. As \stage always creates a new shard, the shards are guaranteed to have non-overlapping ranges.

As an example, we'll describe how to stage data into the github_events table shown above. First, we download and extract two hours of github data.

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-0.csv.gz
    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-1.csv.gz
    gzip -d github_events-2015-01-01-0.csv.gz
    gzip -d github_events-2015-01-01-1.csv.gz

Then, we first merge both files into a single file by using the cat command.

::

    cat github_events-2015-01-01-0.csv github_events-2015-01-01-1.csv > github_events-2015-01-01-0-1.csv

Next, we sort the data on the repo_id column using the linux sort command.

::

    sort -n --field-separator=',' --key=4 github_events-2015-01-01-0-1.csv > github_events_sorted.csv

Finally, we can split the input data such that no two files have any overlapping partition column ranges. This can be done by writing a custom script or manually ensuring that files don’t have overlapping ranges of the repo_id column.

For this example, we download and extract data that has been previously split on the basis of repo_id.
    
::

    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range1.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range2.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range3.csv.gz 
    wget http://examples.citusdata.com/github_archive/github_events_2015-01-01-0-1_range4.csv.gz
    gzip -d github_events_2015-01-01-0-1_range1.csv.gz
    gzip -d github_events_2015-01-01-0-1_range2.csv.gz
    gzip -d github_events_2015-01-01-0-1_range3.csv.gz
    gzip -d github_events_2015-01-01-0-1_range4.csv.gz

Then, we load the files using the \stage command.

::

    /opt/citusdb/4.0/bin/psql -h localhost -d postgres
    \stage github_events from 'github_events_2015-01-01-0-1_range1.csv' with csv;
    \stage github_events from 'github_events_2015-01-01-0-1_range2.csv' with csv;
    \stage github_events from 'github_events_2015-01-01-0-1_range3.csv' with csv;
    \stage github_events from 'github_events_2015-01-01-0-1_range4.csv' with csv;

After this point, you can run queries on the range distributed table. To generate per-repository metrics, your queries would generally have filters on the repo_id column. Then, CitusDB can easily prune away unrelated shards and ensure that the query hits only one shard. Also, groupings and orderings on the repo_id can be easily pushed down the worker nodes leading to more efficient queries. We also note here that all the commands which can be run on tables using the append distribution method can be run on tables using range distribution. This includes \stage, the append and shard creation UDFs and the delete UDF. 

The difference between range and append methods is that CitusDB’s distributed query planner has extra knowledge that the shards have distinct non-overlapping distribution key ranges. This allows the planner to push down more operations to the worker nodes so that they can be executed in parallel. This reduces both the amount of data transferred across network and the amount of computation to be done for aggregation at the master node.

With this, we end our discussion of how you can create and modify append, hash and range distributed tables using CitusDB. In the section below, we discuss how you can run your analytics queries. Please note that the sections below are independent of the distribution method chosen.
