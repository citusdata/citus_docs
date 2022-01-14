.PHONY: docs watch clean

docs:
	sphinx-build -b html -W -n . _build

watch:
	sphinx-autobuild -b html -W -a -n . _build

clean:
	rm -rf _build
