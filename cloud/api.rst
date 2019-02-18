Formation API
#############

.. note::

   Cloud API access is available upon request. Open a :ref:`support ticket <cloud_support>` to enable it for your account.

Citus Cloud provides an API to list, delete, and create formations within an organization. This is a convenient way to manage frequent formation changes.

Authentication
==============

All formation API requests must include an authentication token. To get one, visit the `tokens <https://console.citusdata.com/api_tokens>`_ page, accessible through the Cloud menu bar in ``Org > API Tokens``:

.. image:: ../images/cloud-api-get-token.png

Create a token with a name that's meaningful to you. The name does not affect the API, it exists so you can revoke the token later if desired. Tokens last for one year.

.. image:: ../images/cloud-api-name-token.png

After generating the token, its value will be displayed just once. Copy it to a secure place because it will never be visible again from the Cloud console.

In the examples below, we will assume that the token is assigned to an environment variable in the shell:

.. code-block:: bash

   # save to an environment variable for convenience

   export API_TOKEN=<token>

The token is in `JWT <https://jwt.io/>`_ format, and should be added to HTTPS requests using the ``Authorization`` header:

.. code-block:: text

   Authorization: Token API_TOKEN

For security, all requests must be issued over https. Additionally, API requests are limited to five per minute.

Create Formation
================

* Endpoint: POST https://console.citusdata.com/api/v1/formations/
* Sample request payload:

  .. code-block:: json

    {
       "name": "my-formation",
       "region": "us-east-1",
       "tune_attributes": {
          "coordinator_tune": "t2.small",
          "worker_tune": "t2.small",
          "coordinator_ha": false,
          "worker_ha": false,
          "worker_count": "2",
          "coordinator_disk_size": "100",
          "worker_disk_size": "100"
       }
    }

  Parameters:

  * (mandatory) **name**: a non-empty string of your choice
  * (mandatory) **region**: any of our :ref:`cloud_regions`
  * (mandatory) **coordinator_tune**, **worker_tune**: a tune is any of these AWS machine types: t2.small, t2.medium, t2.large,  r3.large, r3.xlarge, r3.2xlarge, r3.4xlarge, r3.8xlarge r4.large, r4.xlarge, r4.2xlarge, r4.4xlarge, r4.8xlarge, r4.16xlarge, r5.large, r5.xlarge, r5.2xlarge, r5.4xlarge, r5.12xlarge, r5.24xlarge, c4.xlarge, c4.2xlarge, c4.4xlarge, c4.8xlarge, c5.xlarge, c5.2xlarge, c5.4xlarge, c5.9xlarge. *(If you choose a tune from the t2.\* series, both the coordinator_tune and worker_tune must be same.)*
  * (mandatory) **coordinator_disk_size**, **worker_disk_size**: size in gigabytes. May be any of the values 100, 512, 1024, 1536, 2048, or 2560.  *(If you choose a tune from the t2.\* series, the disk size must be 100.)*
  * (mandatory) **worker_count**: numeric value less than or equal to 40
  * **coordinator_ha**, **worker_ha**: whether to enable High Availability. Default is false.

* Example:

   .. code-block:: bash

     curl -H "Authorization: Token $API_TOKEN" \
          -H "Content-Type: application/json" \
          --request POST \
          -d '{"tune_attributes": { "coordinator_tune": "t2.small", "worker_tune": "t2.small", "worker_count": "2", "coordinator_disk_size": "100", "worker_disk_size": "100"}, "name": "my-formation", "region": "us-east-1"}' \
          https://console.citusdata.com/api/v1/formations/

* Response:

  .. code-block:: json

    {
      "id": "0123456789abcdef0123456789a"
    }

List Formations
===============

* Endpoint: GET https://console.citusdata.com/api/v1/formations/
* Example:

  .. code-block:: bash

    curl -H "Authorization: Token $API_TOKEN" \
      https://console.citusdata.com/api/v1/formations/

* Response:

  .. code-block:: json

    {
      "formations": [
        {
          "id": "0123456789abcdef0123456789a",
          "name": "my-formation",
          "region": "us-east-1",
          "created_at": "2019-01-01T00:00:00Z"
        }
      ]
    }

  The id attribute identifies the formation and is required to destroy a formation or get its details.

Formation Details
=================

* Endpoint: GET https://console.citusdata.com/api/v1/formations/**:formation_id**
* Example:

  .. code-block:: bash

    curl -H "Authorization: Token $API_TOKEN" \
      https://console.citusdata.com/api/v1/formations/0123456789abcdef0123456789a

* Response:

  .. code-block:: json

    {
      "id": "0123456789abcdef0123456789a",
      "name": "my-formation",
      "state": "steady",
      "region": "us-east-1",
      "created_at": "2019-01-01T00:00:00Z",
      "tune_attributes": {
        "is_mx": false,
        "is_zfs": false,
        "worker_ha": false,
        "worker_tune": "t2.small",
        "worker_disk_size": "100",
        "worker_count": 2,
        "coordinator_ha": false,
        "coordinator_tune": "t2.small",
        "coordinator_disk_size": "100"
      },
      "database_url": "postgres://foo:bar@host:5432/db?sslmode=require"
    }

  Possible states include: steady, creating, converging, ready, archiving, and archived.

Destroy Formation
=================

* Endpoint: DELETE https://console.citusdata.com/api/v1/formations/**:formation_id**
* Example:

   .. code-block:: bash

     curl -H "Authorization: Token $API_TOKEN" --request DELETE \
       https://console.citusdata.com/api/v1/formations/0123456789abcdef0123456789a

* Response:

  .. code-block:: json

    {
      "success": true
    }

