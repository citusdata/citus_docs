#### Sphinx source files for Citus documentation

To generate HTML version:

1. Install Sphinx from the [sphinx website](http://sphinx-doc.org/latest/install.html)
2. Clone this repository
4. Generate HTML
    ```bash
    cd citus_docs
    sphinx-build -b html -a -n . _build

    # open _build/index.html in your browser
    ```
