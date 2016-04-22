.. _distributed_query_planner:

Distributed Query Planner
#########################

CitusDB’s distributed query planner takes in a SQL query and plans it for distributed execution.

For SELECT queries, the planner first creates a plan tree of the input query and transforms it into its commutative and associative form so it can be parallelized. It also applies several optimizations to ensure that the queries are executed in a scalable manner, and that network I/O is minimized.

Next, the planner breaks the query into two parts - the master query which runs on the master node and the worker query fragments which run on individual shards on the worker nodes. The planner then assigns these query fragments to the worker nodes such that all their resources are used efficiently. After this step, the distributed query plan is passed on to the distributed executor for execution.

For INSERT, UPDATE and DELETE queries, CitusDB requires that the query hit exactly one shard. Once the planner receives an incoming query, it needs to decide the correct shard to which the query should be routed. To do this, it hashes the partition column in the incoming row and looks at hash tokens for the shards in the metadata to determine the right shard for the query. Then, the planner rewrites the SQL of that command to reference the shard table instead of the original table. This re-written plan is then passed to the distributed executor.
