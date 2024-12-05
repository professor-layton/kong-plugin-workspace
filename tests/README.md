# kong-pongo
https://github.com/Kong/kong-pongo

## .pongo/pongo-setup.sh:
pongo-setup.sh is ran upon container start inside the Kong container. It will not be executed but sourced, and will run on /bin/bash as interpreter.

## .pongo/pongorc
Pongo can use a set of test dependencies that can be used to test against. A way of specifying the dependencies is by adding them to the .pongo/pongorc file.

