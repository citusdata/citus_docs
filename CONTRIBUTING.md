# Contributing to Citus

We're happy you want to contribute! You can help us in different ways:

* Open an [issue](https://github.com/citusdata/citus_docs/issues) with
  suggestions for improvements
* Fork this repository and submit a pull request

Before accepting any code contributions we ask that contributors
sign a Contributor License Agreement (CLA). For an explanation of
why we ask this as well as instructions for how to proceed, see the
[Microsoft CLA](https://cla.opensource.microsoft.com/).


## Building and previewing the docs locally

To generate an HTML version:

1. Create a Python [virtual
   environment](https://docs.python.org/3/library/venv.html) and activate it.

   ```bash
   # in the citus_docs repo directory

   python3.9 -m venv .venv
   source .venv/bin/activate
   ```

   (The version of sphinx pinned by the project does not work with python
   3.10+.)

1. Install the [Sphinx](http://www.sphinx-doc.org) documentation system and the
   Citus theme:

   ```bash
   pip install -r requirements.txt
   ```

1. Generate the HTML docs preview:

   ```bash
   make

   # open _build/index.html in your browser
   ```

   Alternately, you can run a local development server to automatically rebuild
   a docs preview as you edit files.

   ```bash
   pip install sphinx-autobuild
   make watch

   # open http://127.0.0.1:8000 in your browser
   ```
