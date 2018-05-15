Query Tools
###########

Business Intelligence with Tableau
==================================

`Tableau <https://www.tableau.com/>`_ is a popular business intelligence and analytics tool for databases. Citus and Tableau provide a seamless experience for performing ad-hoc reporting or analysis.

You can now interact with Tableau using the following steps.

* Choose PostgreSQL from the "Add a Connection" menu.

  .. image:: ../images/tableau-add-connection.png
* Enter the connection details for the coordinator node of your Citus cluster. (Note if you're connecting to Citus Cloud you must select "Require SSL.")

  .. image:: ../images/tableau-connection-details.png
* Once you connect to Tableau, you will see the tables in your database. You can define your data source by dragging and dropping tables from the “Table” pane. Or, you can run a custom query through “New Custom SQL”.
* You can create your own sheets by dragging and dropping dimensions, measures, and filters. You can also create an interactive user interface with Tableau. To do this, Tableau automatically chooses a date range over the data. Citus can compute aggregations over this range in human real-time.

.. image:: ../images/tableau-visualization.jpg
