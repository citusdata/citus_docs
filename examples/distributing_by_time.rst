.. distributing_by_time.rst

Distributing by Time Dimension (Incremental Data Loading)
##########################################################

Events data generally arrives in a time-ordered series. So, if your use case
works well with batch loading, it is easiest to append distribute your largest
tables by time, and load data into them in intervals of N minutes / hours. Since
the data already comes sorted on the time dimension, you don’t have to do any
extra preprocessing before loading the data. 

In the next few sections, we demonstrate how you can setup a CitusDB cluster which uses
the above approach with the Github events data.


.. toctree::
   :hidden:

   time_querying_raw_data.rst
   time_querying_aggregated_data.rst
