#### Sphinx source files for Citus documentation

To generate HTML version:

1. Install Sphinx from the [sphinx website](http://www.sphinx-doc.org/en/master/usage/installation.html)
2. Clone this repository
4. Generate HTML
    ```bash
    cd citus_docs
    make

    # open _build/index.html in your browser
    ```

---

**Sphinx Installation Note:** on OS X it's better to install sphinx via [pip](https://pip.pypa.io/en/stable/installing/) rather than Homebrew.
(The brew formula is keg-only and used primarily by other tools.)
Use `pip install sphinx`.
