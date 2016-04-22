.. _powering_real_time_dashboards:

Powering real-time analytics dashboards
########################################

A common use case where customers use CitusDB is to power their customer facing
real-time analytics dashboards. This involves providing human real-time (few
seconds or sub-second) responses to queries over billions of “events”. This
event-based data model is applicable to a variety of use cases, like user
actions in mobile application, user clicks on websites / ads, events in an event
stream, or each line in a log file.

We generally see two approaches to capturing and querying high-volume events
data and presenting insights through dashboards or graphs. The first approach
involves distributing the data by the time dimension and works well with batch
loading of data. The second approach distributes the data by identifier and is
more suited to use cases which require users to insert / update their data in
real-time.

We describe these approaches below and provide instructions in context of the
github events example for users who want to try them out. Note that the sections
below assume that you have already downloaded and installed CitusDB. If you
haven’t, please visit the :ref:`installation_index` before proceeding.

.. toctree::
   :maxdepth: 2

   distributing_by_time.rst
   distributing_by_identifier.rst
