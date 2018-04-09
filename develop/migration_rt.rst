Real-Time Analytics Apps
========================

In this model multiple worker nodes calculate aggregate data in parallel for applications such as analytic dashboards. This scenario requires greater interaction between Citus nodes than the multi-tenant case and the transition from a standalone database varies more per application.

In general you can distribute the tables from an existing schema by following the advice in :ref:`performance_tuning`. This will provide a baseline from which you can measure and interactively improve performance. For more migration guidance please `contact us <https://www.citusdata.com/about/contact_us>`_.
