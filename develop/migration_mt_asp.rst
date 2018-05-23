.. _asp_migration:

ASP.NET
=======

In :ref:`mt_schema_migration` we discussed the framework-agnostic database changes required for using Citus in the multi-tenant use case. The current section investigates how to build multi-tenant ASP.NET applications that work with a Citus storage backend.

Example App
-----------

To make this migration section concrete, let's consider a simplified
version of StackExchange. For reference, the final result exists `on
Github <https://github.com/nbarbettini/QuestionExchange>`__.

Schema
~~~~~~

We'll start with two tables:

.. code-block:: sql

    CREATE TABLE tenants (
        id uuid NOT NULL,
        domain text NOT NULL,
        name text NOT NULL,
        description text NOT NULL,
        created_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL
    );

    CREATE TABLE questions (
        id uuid NOT NULL,
        tenant_id uuid NOT NULL,
        title text NOT NULL,
        votes int NOT NULL,
        created_at timestamptz NOT NULL,
        updated_at timestamptz NOT NULL
    );

    ALTER TABLE tenants ADD PRIMARY KEY (id);
    ALTER TABLE questions ADD PRIMARY KEY (id, tenant_id);

Each tenant of our demo application will connect via a different domain
name. ASP.NET Core will inspect incoming requests and look up the domain
in the ``tenants`` table. You could also look up tenants by subdomain
(or any other scheme you want).

Notice how the ``tenant_id`` is also stored in the ``questions``
table?  This will make it possible to :ref:`colocate <colocation>` the
data. With the tables created, use ``create_distributed table`` to tell
Citus to shard on the tenant ID:

.. code-block:: sql

    SELECT create_distributed_table('tenants', 'id');
    SELECT create_distributed_table('questions', 'tenant_id');


Next include some test data.

.. code-block:: sql

    INSERT INTO tenants VALUES (
        'c620f7ec-6b49-41e0-9913-08cfe81199af', 
        'bufferoverflow.local',
        'Buffer Overflow',
        'Ask anything code-related!',
        now(),
        now());

    INSERT INTO tenants VALUES (
        'b8a83a82-bb41-4bb3-bfaa-e923faab2ca4', 
        'dboverflow.local',
        'Database Questions',
        'Figure out why your connection string is broken.',
        now(),
        now());

    INSERT INTO questions VALUES (
        '347b7041-b421-4dc9-9e10-c64b8847fedf',
        'c620f7ec-6b49-41e0-9913-08cfe81199af',
        'How do you build apps in ASP.NET Core?',
        1,
        now(),
        now());

    INSERT INTO questions VALUES (
        'a47ffcd2-635a-496e-8c65-c1cab53702a7',
        'b8a83a82-bb41-4bb3-bfaa-e923faab2ca4',
        'Using postgresql for multitenant data?',
        2,
        now(),
        now());

This completes the database structure and sample data. We can now move
on to setting up ASP.NET Core.

ASP.NET Core project
~~~~~~~~~~~~~~~~~~~~

If you don't have ASP.NET Core installed, install the `.NET Core SDK
from Microsoft <https://dot.net/core>`__.  These instructions will use
the ``dotnet`` CLI, but you can also use Visual Studio 2017 or newer if
you are on Windows.

Create a new project from the MVC template with ``dotnet new``:

::

    dotnet new mvc -o QuestionExchange
    cd QuestionExchange

You can preview the template site with ``dotnet run`` if you'd like. The
MVC template includes almost everything you need to get started, but
Postgres support isn't included out of the box. You can fix this by
installing the
`Npgsql.EntityFrameworkCore.PostgreSQL <https://www.nuget.org/packages/Npgsql.EntityFrameworkCore.PostgreSQL/>`__
package:

::

    dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL

This package adds Postgres support to Entity Framework Core, the default
ORM and database layer in ASP.NET Core. Open the ``Startup.cs`` file and
add these lines anywhere in the ``ConfigureServices`` method:

.. code-block:: csharp

    var connectionString = "connection-string";

    services.AddEntityFrameworkNpgsql()
        .AddDbContext<AppDbContext>(options => options.UseNpgsql(connectionString));

You'll also need to add these declarations at the top of the file:

.. code-block:: csharp

    using Microsoft.EntityFrameworkCore;
    using QuestionExchange.Models;

Replace ``connection-string`` with your Citus connection string. Mine
looks like this:

::

    Server=myformation.db.citusdata.com;Port=5432;Database=citus;Userid=citus;Password=mypassword;SslMode=Require;Trust Server Certificate=true;


.. note::
    
    You can use the `Secret
    Manager <https://docs.microsoft.com/en-us/aspnet/core/security/app-secrets?tabs=visual-studio-code>`__
    to avoid storing your database credentials in code (and accidentally
    checking them into source control).

Next, you'll need to define a database context.

Adding Tenancy to App
---------------------

Define the Entity Framework Core context and models
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The database context class provides an interface between your code and
your database. Entity Framework Core uses it to understand what your
`data
schema <https://msdn.microsoft.com/en-us/library/jj679962(v=vs.113).aspx#Anchor_2>`__
looks like, so you'll need to define what tables are available in your
database.

Create a file called ``AppDbContext.cs`` in the project root, and add
the following code:

.. code-block:: csharp

    using System.Linq;
    using Microsoft.EntityFrameworkCore;
    using QuestionExchange.Models;
    namespace QuestionExchange
    {
        public class AppDbContext : DbContext
        {
            public AppDbContext(DbContextOptions<AppDbContext> options)
                : base(options)
            {
            }

            public DbSet<Tenant> Tenants { get; set; }

            public DbSet<Question> Questions { get; set; }
        }
    }

The two ``DbSet`` properties specify which C# classes to use to model
the rows of each table. You'll create these classes next. Before you do
that, add a new method below the ``Questions`` property:

.. code-block:: csharp

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var mapper = new Npgsql.NpgsqlSnakeCaseNameTranslator();
        var types = modelBuilder.Model.GetEntityTypes().ToList();

        // Refer to tables in snake_case internally
        types.ForEach(e => e.Relational().TableName = mapper.TranslateMemberName(e.Relational().TableName));

        // Refer to columns in snake_case internally
        types.SelectMany(e => e.GetProperties())
            .ToList()
            .ForEach(p => p.Relational().ColumnName = mapper.TranslateMemberName(p.Relational().ColumnName));
    }

C# classes and properties are PascalCase by convention, but your
Postgres tables and columns are lowercase (and snake\_case). The
``OnModelCreating`` method lets you override the default name
translation and let Entity Framework Core know how to find the entities
in your database.

Now you can add classes that represent tenants and questions. Create a
``Tenant.cs`` file in the Models directory:

.. code-block:: csharp

    using System;

    namespace QuestionExchange.Models
    {
        public class Tenant
        {
            public Guid Id { get; set; }

            public string Domain { get; set; }

            public string Name { get; set; }

            public string Description { get; set; }

            public DateTimeOffset CreatedAt { get; set; }

            public DateTimeOffset UpdatedAt { get; set; }
        }
    }

And a ``Question.cs`` file, also in the Models directory:

.. code-block:: csharp

    using System;

    namespace QuestionExchange.Models
    {
        public class Question
        {
            public Guid Id { get; set; }

            public Tenant Tenant { get; set; }

            public string Title { get; set; }

            public int Votes { get; set; }

            public DateTimeOffset CreatedAt { get; set; }

            public DateTimeOffset UpdatedAt { get; set; }
        }
    }

Notice the ``Tenant`` property. In the database, the question table
contains a ``tenant_id`` column. Entity Framework Core is smart enough
to figure out that this property represents a one-to-many relationship
between tenants and questions. You'll use this later when you query your
data.

So far, you've set up Entity Framework Core and the connection to Citus.
The next step is adding multi-tenant support to the ASP.NET Core
pipeline.

Install SaasKit
~~~~~~~~~~~~~~~

`SaasKit <https://github.com/saaskit/saaskit>`__ is an excellent piece
of open-source ASP.NET Core middleware. This package makes it easy to
make your ``Startup`` request pipeline
`tenant-aware <http://benfoster.io/blog/asp-net-5-multitenancy>`__, and
is flexible enough to handle many different multi-tenancy use cases.

Install the
`SaasKit.Multitenancy <https://www.nuget.org/packages/SaasKit.Multitenancy/>`__
package:

::

    dotnet add package SaasKit.Multitenancy

SaasKit needs two things to work: a tenant model and a tenant resolver.
You already have the former (the ``Tenant`` class you created earlier),
so create a new file in the project root called
``CachingTenantResolver.cs``:

.. code-block:: csharp

    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Microsoft.AspNetCore.Http;
    using Microsoft.EntityFrameworkCore;
    using Microsoft.Extensions.Caching.Memory;
    using Microsoft.Extensions.Logging;
    using SaasKit.Multitenancy;
    using QuestionExchange.Models;

    namespace QuestionExchange
    {
        public class CachingTenantResolver : MemoryCacheTenantResolver<Tenant>
        {
            private readonly AppDbContext _context;

            public CachingTenantResolver(
                AppDbContext context, IMemoryCache cache, ILoggerFactory loggerFactory)
                 : base(cache, loggerFactory)
            {
                _context = context;
            }

            // Resolver runs on cache misses
            protected override async Task<TenantContext<Tenant>> ResolveAsync(HttpContext context)
            {
                var subdomain = context.Request.Host.Host.ToLower();

                var tenant = await _context.Tenants
                    .FirstOrDefaultAsync(t => t.Domain == subdomain);

                if (tenant == null) return null;

                return new TenantContext<Tenant>(tenant);
            }

            protected override MemoryCacheEntryOptions CreateCacheEntryOptions()
                => new MemoryCacheEntryOptions().SetAbsoluteExpiration(TimeSpan.FromHours(2));

            protected override string GetContextIdentifier(HttpContext context)
                => context.Request.Host.Host.ToLower();

            protected override IEnumerable<string> GetTenantIdentifiers(TenantContext<Tenant> context)
                => new string[] { context.Tenant.Domain };
        }
    }

The ``ResolveAsync`` method does the heavy lifting: given an incoming
request, it queries the database and looks for a tenant matching the
current domain. If it finds one, it passes a ``TenantContext`` back to
SaasKit. All of tenant resolution logic is totally up to you - you could
separate tenants by subdomains, paths, or anything else you want.

This implementation uses a `tenant caching
strategy <http://benfoster.io/blog/aspnet-core-multi-tenancy-tenant-lifetime>`__
so you don't hit the database with a tenant lookup on every incoming
request. After the first lookup, tenants are cached for two hours (you
can change this to whatever makes sense).

With a tenant model and a tenant resolver ready to go, open up the
``Startup`` class and add this line anywhere inside the
``ConfigureServices`` method:

.. code-block:: csharp

    services.AddMultitenancy<Tenant, CachingTenantResolver>();

Next, add this line to the ``Configure`` method, below
``UseStaticFiles`` but **above** ``UseMvc``:

.. code-block:: csharp

    app.UseMultitenancy<Tenant>();

The ``Configure`` method represents your actual request pipeline, so
order matters!

Update views
~~~~~~~~~~~~

Now that all the pieces are in place, you can start referring to the
current tenant in your code and views. Open up the
``Views/Home/Index.cshtml`` view and replace the whole file with this
markup:

.. code-block:: html

    @inject Tenant Tenant
    @model QuestionListViewModel

    @{
        ViewData["Title"] = "Home Page";
    }

    <div class="row">
        <div class="col-md-12">
            <h1>Welcome to <strong>@Tenant.Name</strong></h1>
            <h3>@Tenant.Description</h3>
        </div>
    </div>

    <div class="row">
        <div class="col-md-12">
            <h4>Popular questions</h4>
            <ul>
                @foreach (var question in Model.Questions)
                {
                    <li>@question.Title</li>
                }
            </ul>
        </div>
    </div>

The ``@inject`` directive gets the current tenant from SaasKit, and the
``@model`` directive tells ASP.NET Core that this view will be backed by
a new model class (that you'll create). Create the
``QuestionListViewModel.cs`` file in the Models directory:

.. code-block:: csharp

    using System.Collections.Generic;

    namespace QuestionExchange.Models
    {
        public class QuestionListViewModel
        {
        public IEnumerable<Question> Questions { get; set; }
        }
    }

Query the database
~~~~~~~~~~~~~~~~~~

The ``HomeController`` is responsible for rendering the index view you
just edited. Open it up and replace the ``Index()`` method with this
one:

.. code-block:: csharp

    public async Task<IActionResult> Index()
    {
        var topQuestions = await _context
            .Questions
            .Where(q => q.Tenant.Id == _currentTenant.Id)
            .OrderByDescending(q => q.UpdatedAt)
            .Take(5)
            .ToArrayAsync();

        var viewModel = new QuestionListViewModel
        {
            Questions = topQuestions
        };

        return View(viewModel);
    }

This query gets the newest five questions for this tenant (granted,
there's only one question right now) and populates the view model.

    For a large application, you'd typically put data access code in a
    service or repository layer and keep it out of your controllers.
    This is just a simple example!

The code you added needs ``_context`` and ``_currentTenant``, which
aren't available in the controller yet. You can make these available by
adding a constructor to the class:

.. code-block:: csharp

    public class HomeController : Controller
    {
        private readonly AppDbContext _context;
        private readonly Tenant _currentTenant;

        public HomeController(AppDbContext context, Tenant tenant)
        {
            _context = context;
            _currentTenant = tenant;
        }

        // Existing code...

To keep the compiler from complaining, add this declaration at the top
of the file:

.. code-block:: csharp

    using Microsoft.EntityFrameworkCore;

Test the app
~~~~~~~~~~~~

The test tenants you added to the database were tied to the (fake)
domains ``bufferoverflow.local`` and ``dboverflow.local``. You'll need
to `edit your hosts
file <https://www.howtogeek.com/howto/27350/beginner-geek-how-to-edit-your-hosts-file/>`__
to test these on your local machine:

::

    127.0.0.1 bufferoverflow.local
    127.0.0.1 dboverflow.local

Start your project with ``dotnet run`` or by clicking Start in Visual
Studio and the application will begin listening on a URL like
``localhost:5000``. If you visit that URL directly, you'll see an error
because you haven't set up any `default tenant
behavior <http://benfoster.io/blog/handling-unresolved-tenants-in-saaskit>`__
yet.

Instead, visit http://bufferoverflow.local:5000 and you'll see one
tenant of your multi-tenant application! Switch to
http://dboverflow.local:5000 to view the other tenant. Adding more
tenants is now a simple matter of adding more rows in the ``tenants``
table.
