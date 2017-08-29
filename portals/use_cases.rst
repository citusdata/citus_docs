:orphan:

.. _use_cases_topic:

Use Cases
#########

After :ref:`getting_started`, it's time to go deeper into the most common use-cases for Citus.

* :ref:`mt_use_case` is a hands-on guide for building the backend of an example ad analytics app. It talks about data modeling for distributed systems, including how to adapt an existing single-machine database schema. It also talks about common challenges for scaling and how to solve them.
* :ref:`rt_use_case` talks about the other prominent Citus use case: super fast, highly parallel aggregate queries. It shows how to model the backend for a web dashboard for event data. It talks about managing constantly increasing data, even when the data is somewhat unstructured.

Once you learn these use-cases in depth, you might want to learn more about :ref:`migrating_topic`, to port your existing application.
