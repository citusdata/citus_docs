:orphan:

.. _django_migration:

Django
------

In :ref:`mt_schema_migration` we discussed the framework-agnostic database changes required for using Citus in the multi-tenant use case. Here we investigate specifically how to migrate multi-tenant Django applications to a Citus storage backend.

Preparing to scale-out a multi-tenant application
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Initially you’ll start with all tenants placed on a single database node. Django's typical conventions make some assumptions about the data storage which limit scale-out options.

In particular, the ORM introduces a pattern where you normalize data and split it into many distinct models each identified by a single ``id`` column (usually added implicitly by the ORM). For instance, consider this simplified model:

.. code-block:: python

  from django.utils import timezone
  from django.db import models

  class Store(models.Model):
    name = models.CharField(max_length=255)
    url = models.URLField()

  class Product(models.Model):
    name = models.CharField(max_length=255)
    description = models.TextField()
    price = models.DecimalField(max_digits=6, decimal_places=2),
    quantity = models.IntegerField()

    store = models.ForeignKey(Store, on_delete=models.CASCADE)

  class Purchase(models.Model):
    ordered_at = models.DateTimeField(default=timezone.now)
    billing_address = models.TextField()
    shipping_address = models.TextField()

    product = models.ForeignKey(Product, on_delete=models.CASCADE)

The tricky thing with this pattern is that in order to find all purchases for a store, you'll have to query for all of a store's products first. This becomes a problem once you start sharding data, and in particular when you run UPDATE or DELETE queries on nested models like purchases in this example.

**1. Introduce a column for the store\_id on every record that belongs to a store**

In order to scale out a multi-tenant model, it's essential that you can locate all records that belong to a store quickly. The easiest way to achieve this is to simply add a :code:`store_id` column on every object that belongs to a store. In our case:

.. code-block:: python

  class Purchase(models.Model):
    ordered_at = models.DateTimeField(default=timezone.now)
    billing_address = models.TextField()
    shipping_address = models.TextField()

    store = models.ForeignKey(  ## Add this
      Store, null=True,         ##
      on_delete=models.CASCADE  ##
    )                           ##

    product = models.ForeignKey(Product, on_delete=models.CASCADE)

Create a migration to reflect the change: :code:`./manage.py makemigrations`.

**2. Include the store\_id in all primary keys**

Primary-key constraints on values other than the tenant\_id
will present a problem in any distributed system, since it’s difficult
to make sure that no two nodes accept the same unique value. Enforcing
the constraint would require expensive scans of the data across all
nodes.

To solve this problem, for the models which are logically related
to a store (the tenant for our app), you should add store\_id to
the primary keys, effectively scoping objects unique inside a given
store. This helps add the concept of tenancy to your models, thereby
making the multi-tenant system more robust.

Django automatically creates a simple "id" primary key on models, so we will need to circumvent that behavior with a custom migration of our own. Run :code:`./manage.py makemigrations appname --empty --name remove_simple_pk`, and edit the result to look like this:

.. code-block:: python

  from django.db import migrations

  class Migration(migrations.Migration):

    dependencies = [
      # leave this as it was generated
    ]

    operations = [
      # Django considers "id" the primary key of these tables, but
      # we want the primary key to be (store_id, id)
      migrations.RunSQL("""
        ALTER TABLE appname_product
        DROP CONSTRAINT appname_product_pkey CASCADE;

        ALTER TABLE appname_product
        ADD CONSTRAINT appname_product_pkey
        PRIMARY KEY (store_id, id)
      """),
      migrations.RunSQL("""
        ALTER TABLE appname_purchase
        DROP CONSTRAINT appname_purchase_pkey CASCADE;

        ALTER TABLE appname_purchase
        ADD CONSTRAINT appname_purchase_pkey
        PRIMARY KEY (store_id, id)
      """),
    ]

**3. Switch to TenantModel**

Next, we'll use the `django-multitenant <https://github.com/citusdata/django-multitenant>`_ library to add store_id to foreign keys, and make application queries easier later on.

In requirements.txt for your Django application, add

::

  django_multitenant>=1.1.0

Run ``pip install -r requirements.txt``.

In settings.py, change the database engine to the customized engine provied by django-multitenant:

.. code-block:: python

  'ENGINE': 'django_multitenant.backends.postgresql'

Add a few more imports to your models file:

.. code-block:: python

  from django_multitenant.models import *
  from django_multitenant.fields import *

Change all the models to inherit from ``TenantModel`` rather than ``Model``, set the tenant\_id on each model, and use ``TenantForeignKey`` rather than ``ForeignKey`` for any foreign key which does not already contain the tenant\_id.

.. code-block:: python

  class Store(TenantModel):
    name = models.CharField(max_length=255)
    url = models.URLField()
    tenant_id = "id"

  class Product(TenantModel):
    name = models.CharField(max_length=255)
    description = models.TextField()
    price = models.DecimalField(max_digits=6, decimal_places=2),
    quantity = models.IntegerField()

    store = models.ForeignKey(Store, on_delete=models.CASCADE)
    tenant_id = "store_id"

  class Purchase(TenantModel):
    ordered_at = models.DateTimeField(default=timezone.now)
    billing_address = models.TextField()
    shipping_address = models.TextField()

    store = models.ForeignKey(Store, null=True, on_delete=models.CASCADE)
    tenant_id = "store_id"

    product = TenantForeignKey(Product, on_delete=models.CASCADE)

After installing the library, changing the engine, and updating the models, run
:code:`./manage.py makemigrations`. This will produce a migration to make the foreign keys composite when necessary.

**4. Distribute data in Citus**

We need one final migration to tell Citus to mark tables for distribution. Create a new migration :code:`./manage.py makemigrations appname --empty --name distribute_tables`. Edit the result to look like this:

.. code-block:: python

  from django.db import migrations

  class Migration(migrations.Migration):
    dependencies = [
      # leave this as it was generated
    ]

    operations = [
      migrations.RunSQL(
        "SELECT create_distributed_table('mtdjango_store','id')"
      ),
      migrations.RunSQL(
        "SELECT create_distributed_table('mtdjango_product','store_id')"
      ),
      migrations.RunSQL(
        "SELECT create_distributed_table('mtdjango_purchase','store_id')"
      ),
    ]

With all the migrations created from the steps so far, apply them to the database with ``./manage.py migrate``.

There's one more little detail. Server-side cursors do not work well with Citus. Go back to the database configuration in `settings.py` and include the following parameter:

.. code-block:: python

  DATABASES = {
    'default': {
        'DISABLE_SERVER_SIDE_CURSORS': True
    },
  }

At this point the Django application models are ready to work with a Citus backend. You can continue by importing data to the new system and modifying controllers as necessary to deal with the model changes.

Updating the Django Application
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The django-multitenant library discussed in the previous section is not only useful for migrations, but for simplifying application queries. The library allows application code to easily scope queries to a single tenant. It automatically adds the correct SQL filters to all statements, including fetching objects through relations.

For instance, in a controller simply ``set_current_tenant`` and all the queries or joins afterward will include a filter to scope results to a single tenant.

.. code-block:: python

  # set the current tenant to the first store
  s = Store.objects.all()[0]
  set_current_tenant(s)

  # now this count query applies only to Products for that store
  Product.objects.count()

  # Find purchases for risky products in the current store
  Purchase.objects.filter(product__description='Dangerous Toy')

In the context of an application controller, the current tenant object can be stored as a SESSION variable when a user logs in, and controller actions can :code:`set_current_tenant` to this value. See the README in django-multitenant for more examples.
