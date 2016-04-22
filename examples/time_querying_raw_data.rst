.. _time_querying_raw_data:

Querying Raw Data
##################

We first insert raw events data into the database distributed on the time
dimension. This assumes that we have enough hardware to generate query results
in real-time. This approach is the simplest to setup and provides the most
flexibility in terms of dimensions on which the queries can be run.

**1. Download sample data**

We begin by downloading and extracting the sample data for 6 hours of github
data. We have also transformed more sample data for users who want to try the
example with larger volumes of data. Please contact us at engage@citusdata.com
if you want to run this example with a larger dataset.

::

    wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz

    gzip -d github_events-2015-01-01-*.gz

**2. Connect to the master node and create a distributed table**

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
    ) DISTRIBUTE BY APPEND (created_at);

This command creates a new distributed table, and has almost the same syntax as
PostgreSQL's `CREATE TABLE <http://www.postgresql.org/docs/9.4/static/sql-createtable.html>`_ command. The only difference is that the command has a
distribute by append clause at the end, which tells the database the column to
use for distribution. This method doesn't enforce a particular distribution; it
merely tells the database to keep minimum and maximum values for the created_at
column in each shard. This helps CitusDB to optimize queries with time
qualifiers by pruning away unrelated shards.

To learn more about different distribution methods in CitusDB, you can visit the
:ref:`related section<distribution_method>` in our user guide.

**3. Create desired indexes**

Most of your queries may have an inherent time dimension, but you may still want
to query data on secondary dimensions at times, and that's when creating an
index comes in handy. In this example, we create an index on repo_id as we have
queries where we want to  generate statistics / graphs only for a particular
repository.

::

    CREATE INDEX repo_id_index ON github_events (repo_id);

Note that indexes visibly increase data loading times in PostgreSQL, so you may
want to skip this step if you don't need them.

**4. Load Data**

Now, we’re ready to load these events into the database by specifying the
correct file path. Please note that you can load these files in parallel through
separate database connections or from different nodes. We also enable timing so
that we can view the loading and query times.

::

    \timing
    \stage github_events from 'github_events-2015-01-01-0.csv' with CSV

    SELECT count(*) from github_events;

    \stage github_events from 'github_events-2015-01-01-1.csv' with CSV

    SELECT count(*) from github_events;

    \stage github_events from 'github_events-2015-01-01-2.csv' with CSV
    \stage github_events from 'github_events-2015-01-01-3.csv' with CSV
    \stage github_events from 'github_events-2015-01-01-4.csv' with CSV
    \stage github_events from 'github_events-2015-01-01-5.csv' with CSV

The \stage command borrows its syntax from the `client-side
copy <http://www.postgresql.org/docs/9.4/static/app-psql.html>`_ command in
PostgreSQL. Behind the covers, the command opens a connection to the master node
and fetches candidate worker nodes to create new shards on. The command then
connects to these worker nodes, creates at least one shard there, and uploads
the github events to the shards. The command then replicates these shards on
other worker nodes till the replication factor is satisfied, and then finalizes
the shard's metadata with the master node.

Also, you can notice that the times for the count query remain similar even
after adding more data into the cluster. This is because CitusDB now
parallelizes the same query across more cores on your machine.

**5. Run queries**

After creating the table and staging data into it, you are now ready to run
analytics queries on it. We use the psql command prompt to issue queries, but
you could also use a graphical user interface.

::

    -- Find the number of each event type on a per day and per hour graph for a particular repository. 
    SELECT
        event_type, date_part('hour', created_at) as hour, to_char(created_at, 'day'), count(*)
    FROM
        github_events
    WHERE
        repo_id = '724712'
    GROUP BY
        event_type, date_part('hour', created_at), to_char(created_at, 'day')
    ORDER BY
        event_type, date_part('hour', created_at), to_char(created_at, 'day');

    -- Find total count of issues opened, closed, and reopened in the first 3 hours of Jan 1, 2015.
    SELECT
        payload->'action', count(*)
    FROM
        github_events
    WHERE
        event_type = 'IssuesEvent' AND
        created_at >= '2015-01-01 00:00:00' AND
        created_at <= '2015-01-01 02:00:00'
    GROUP BY
        payload->'action';

Other than the sample queries mentioned above, you can also run several other
interesting queries over the github dataset.

With huge volumes of raw data, the hardware requirements of a cluster to get
real-time query responses might not be cost effective. Also, you might not use
all the fields being captured about your events. Hence, you can aggregate
their data on the time dimension and query the aggregated data to get fast query
responses. In the next section, we discuss several approaches to aggregate the
data and also provide instructions for trying them out.
