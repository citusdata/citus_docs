Django
------

At the start of this section we discussed the framework-agnostic database changes required for using Citus in the multi-tenant use case. This section investigates specifically how to migrate multi-tenant Django applications to a Citus storage backend.

Preparing to scale-out a multi-tenant application
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Initially you’ll often start with all tenants placed on a single database node, and using a framework like Django to load the data for a given tenant when you serve a web request that returns the tenant’s data.

Django's typical conventions make a few assumptions about the data storage that limit scale-out options. In particular, the ORM introduces a pattern where you normalize data and split it into many distinct models each identified by a single ``id`` column (usually added implicitly by the ORM). For instance, consider this simplified model:

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
      store = models.ForeignKey(Store)

  class Purchase(models.Model):
      ordered_at = models.DateTimeField(default=timezone.now)
      billing_address = models.TextField()
      shipping_address = models.TextField()

      product = models.ForeignKey(Product)

The tricky thing with this pattern is that in order to find all purchases for a store, you'll have to query for all of a store's products first. This becomes a problem once you start sharding data, and in particular when you run UPDATE or DELETE queries on nested models like purchases in this example.

**1. Introduce a column for the store\_id on every record that belongs to a store**

In order to scale out a multi-tenant model, it's essential that you can locate all records that belong to a store quickly. The easiest way to achieve this is to simply add a :code:`store_id` column on every object that belongs to a store, and backfill your existing data to have this column set correctly.

**2. Use UNIQUE constraints which include the store\_id**

Unique and foreign-key constraints on values other than the tenant\_id
will present a problem in any distributed system, since it’s difficult
to make sure that no two nodes accept the same unique value. Enforcing
the constraint would require expensive scans of the data across all
nodes.

To solve this problem, for the models which are logically related
to a store (the tenant for our app), you should add store\_id to
the constraints, effectively scoping objects unique inside a given
store. This helps add the concept of tenancy to your models, thereby
making the multi-tenant system more robust.

Let's begin by adjusting our model definitions and have Django generate a new migration for the two changes discussed.

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
    store = models.ForeignKey(Store)

    class Meta(object):                  # added
      unique_together = ["id", "store"]  #

  class Purchase(models.Model):
    ordered_at = models.DateTimeField(default=timezone.now)
    billing_address = models.TextField()
    shipping_address = models.TextField()

    product = models.ForeignKey(
      Product,
      db_constraint=False                # added
    )
    store = models.ForeignKey(Store)     # added

    class Meta(object):                  # added
      unique_together = ["id", "store"]  #

Create a migration to reflect the change: :code:`./manage.py makemigrations`.

Next we need some custom migrations to adapt the existing key structure in the database for compatibility with Citus. To keep these migrations separate from the ones for the ordinary application, we'll make a new citus application in the same Django project.

.. code-block:: bash

  # Make a new sub-application in the project
  django-admin startapp citus

Edit :code:`appname/settings.py` and add :code:`'citus'` to the array :code:`INSTALLED_APPS`.

Next we'll add a custom migration to remove simple primary keys which will become composite: :code:`./manage.py makemigrations citus --empty --name remove_simple_pk`. Edit the result to look like this:

.. code-block:: python

  from __future__ import unicode_literals
  from django.db import migrations

  class Migration(migrations.Migration):
    dependencies = [
      ('appname', '<name of latest migration>')
    ]

    operations = [
      # Django considers "id" the primary key of these tables, but
      # the database mustn't, because the primary key will be composite
      migrations.RunSQL(
        "ALTER TABLE mtdjango_product DROP CONSTRAINT mtdjango_product_pkey;",
        "ALTER TABLE mtdjango_product ADD CONSTRAINT mtdjango_product_pkey PRIMARY KEY (store_id, id)"
      ),
      migrations.RunSQL(
        "ALTER TABLE mtdjango_purchase DROP CONSTRAINT mtdjango_purchase_pkey;",
        "ALTER TABLE mtdjango_purchase ADD CONSTRAINT mtdjango_purchase_pkey PRIMARY KEY (store_id, id)"
      ),
    ]

Next, we'll make one to tell Citus to mark tables for distribution. :code:`./manage.py makemigrations citus --empty --name distribute_tables`. Edit the result to look like this:

.. code-block:: python

  from __future__ import unicode_literals
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

Finally, we'll establish a composite foreign key. :code:`./manage.py makemigrations citus --empty --name composite_fk`.

.. code-block:: python

  from __future__ import unicode_literals
  from django.db import migrations

  class Migration(migrations.Migration):
    dependencies = [
      # leave this as it was generated
    ]

    operations = [
      migrations.RunSQL(
        """
            ALTER TABLE mtdjango_purchase
            ADD CONSTRAINT mtdjango_purchase_product_fk
            FOREIGN KEY (store_id, product_id)
            REFERENCES mtdjango_product (store_id, id)
            ON DELETE CASCADE;
        """,
        "ALTER TABLE mtdjango_purchase DROP CONSTRAINT mtdjango_purchase_product_fk"
      ),
    ]

Apply the migrations by running :code:`./manage.py migrate`.

**3. Disable server-side cursors**

Edit your database configuration in your `settings.py` file to include the following parameter:

.. code-block:: python

  DATABASES = {
    'default': {
        'DISABLE_SERVER_SIDE_CURSORS': True
    },
  }

At this point the Django application models are ready to work with a Citus backend. You can continue by importing data to the new system and modifying controllers as necessary to deal with the model changes.

Updating the Django Application
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To simplify queries in the Django application, Citus has developed a Python library called `django-multitenant <https://github.com/citusdata/django-multitenant>`_ (still in beta as of this writing). Include :code:`django-multitenant` in the :code:`requirements.txt` package file for your project, and then modify your models.

First, include the library in models.py:

.. code-block:: python

  from django_multitenant import *

Next, change the base class for each model from :code:`models.Model` to :code:`TenantModel`, and add a property specifying the name of the tenant id. For instance, to continue the earlier example:

.. code-block:: python

  class Store(TenantModel):
    tenant_id = 'id'
    # ...

  class Product(TenantModel):
    tenant_id = 'store_id'
    # ...

  class Purchase(TenantModel):
    tenant_id = 'store_id'
    # ...

No extra database migration is necessary beyond the steps in the previous section. The library allows application code to easily scope queries to a single tenant. It automatically adds the correct SQL filters to all statements, including fetching objects through relations.

For instance:

.. code-block:: python

  # set the current tenant to the first store
  s = Store.objects.all()[0]
  set_current_tenant(s)

  # now this count query applies only to Products for that store
  Product.objects.count()

  # Find purchases for risky products in the current store
  Purchase.objects.filter(product__description='Dangerous Toy')

In the context of an application controller, the current tenant object can be stored as a SESSION variable when a user logs in, and controller actions can :code:`set_current_tenant` to this value.
