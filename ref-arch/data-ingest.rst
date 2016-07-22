Data Ingest
###########

- We'll hash distribute the raw data on zone_id
  - Dashboard queries hit a single shard.

.. code-block:: sql

  CREATE TABLE http_requests (
    zone_id INT,
    ingest_time TIMESTAMPTZ DEFAULT now(),

    session_id UUID,
    url TEXT,
    request_country TEXT,
    ip_address CIDR,

    status_code INT,
    response_time_msec INT,
  )
  SELECT master_create_distributed_table('http_requests', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests', [see below], 2);

If you tried to run the above code you might have been made aware that '[see below]' isn't
a valid integer. master_create_worker_shards takes three arguments, the distributed table,
the number of shards to make, and the number of replicas each shard should consist of.

- Replication factor is > 1, which means data is written to multiple places. You aren't
  affected by node failure

- Does cloud have a different signature I should call out?

- Sizing: you should make 1 per worker?
- Sizing: you should make 2-4x the number of cores
  http://docs.citusdata.com/en/v5.1/faq/faq.html#how-do-i-choose-the-shard-count-when-i-hash-partition-my-data

.. code-block:: sql

  CREATE TABLE http_requests_1min (
        zone_id INT,
        ingest_time TIMESTAMPTZ,

        error_count INT,
        success_count INT,
        average_response_time_msec INT,

        distinct_sessions hll, -- TODO: Dont add this column until the relevant section
        country_counters JSONB, -- TODO: same
  )
  SELECT master_create_distributed_table('http_requests_1min', 'zone_id', 'hash');
  SELECT master_create_worker_shards('http_requests_1min', [same as above], 2);
  
  -- indexes aren't automatically created by Citus
  -- this will create the index on all shards
  CREATE INDEX ON http_requests_1min (zone_id, ingest_time);

- We also have count-min sketch if you want percentile queries

- Run the data ingest script we've provided and some of these example queries

- As described in the introduction, this has a few problems. In the next section we
  introduce rollups to solve those problems.
