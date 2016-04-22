.. _examples_index:

Examples
#########

In this section, we discuss how users can use CitusDB to address their real-time
use cases. These examples include powering real-time analytic dashboards on
events or metrics data; tracking unique counts; performing session analytics;
rendering real-time maps using geospatial data types and indexes; and querying
distributed and local PostgreSQL tables in the same database.

In our examples, we use public events data from `GitHub <https://www.githubarchive.org/>`_.
This data has information for about `20+ event types <https://developer.github.com/v3/activity/events/types/>`_
that range from new commits and fork
events to opening new tickets, commenting, and adding members to a project.
These events are aggregated into hourly archives, with each archive containing
JSON encoded events as reported by the GitHub API. For our examples, we slightly
modified these data to include both structured tabular and semi-structured jsonb
fields.

We begin by describing how users can use CitusDB to power their real-time
customer-facing analytics dashboards.

.. toctree::
   :maxdepth: 2
   
   powering_real_time_dashboards.rst

