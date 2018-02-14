Monitoring
##########

Resources Usage
===============

Citus Cloud metrics enable you to get information about your cluster's health and performance. The "Metrics" tab of the Cloud Console provides graphs for a number of measurements, all viewable per node:

* CPU Utilization (Percent)
   .. image:: ../images/metric-cpu.png
* Network - Bytes In / Second
   .. image:: ../images/metric-network-in.png
* Network - Bytes Out / Second
   .. image:: ../images/metric-network-out.png
* Read IOPS
   .. image:: ../images/metric-iops-read.png
* Write IOPS
   .. image:: ../images/metric-iops-write.png
* Bytes Read / Second
   .. image:: ../images/metric-bytes-read.png
* Bytes Written / Second
   .. image:: ../images/metric-bytes-write.png
* Average Read Latency (Seconds)
   .. image:: ../images/metric-latency-read.png
* Average Write Latency (Seconds)
   .. image:: ../images/metric-latency-write.png
* Average Queue Length (Count)
   .. image:: ../images/metric-queue.png
* WAL Bytes Written / Second
   .. image:: ../images/metric-wal.png

Formation Events Feed
=====================

To monitor events in the life of a formation with outside tools via a standard format, we offer RSS feeds per organization. You can use a feed reader or RSS Slack integration (e.g. on an :code:`#ops` channel) to keep up to date.

On the upper right of the "Formations" list in the Cloud console, follow the "Formation Events" link to the RSS feed.

.. image:: ../images/cloud-formation-events.png

The feed includes entries for three types of events, each with the following details:

**Server Unavailable**

This is a notification of connectivity problems such as hardware failure.

*  Formation name
*  Formation url
*  Server

**Failover Scheduled**

For planned upgrades, or when operating a formation without high availability that experiences a failure, this event will appear to indicate a future planned failover event.

*  Formation name
*  Formation url
*  Leader
*  Failover at

For planned failovers, "failover at" will usually match your maintenance window. Note that the failover might happen at this point or shortly thereafter, once a follower is available and has caught up to the primary database.

**Failover**

Failovers happen to address hardware failure, as mentioned, and also for other reasons such as performing system software upgrades, or transferring data to a server with better hardware.

*  Formation name
*  Formation url
*  Leader
*  Situation
*  Follower

Systemic Cloud Status
=====================

Any events affecting the Citus Cloud platform as a whole are recorded on `status.citusdata.com <https://status.citusdata.com/>`_.

.. raw:: html

  <script type="text/javascript">
  analytics.track('Doc', {page: 'monitoring', section: 'cloud'});
  </script>
