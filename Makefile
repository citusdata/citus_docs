docs:
	sphinx-build -b html -W -n . _build

clean:
	rm -rf _build
