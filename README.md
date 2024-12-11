# kong-pongo
https://github.com/Kong/kong-pongo

## .pongo/pongo-setup.sh:
pongo-setup.sh is ran upon container start inside the Kong container. It will not be executed but sourced, and will run on /bin/bash as interpreter.

## .pongo/pongorc
pongo can use a set of test dependencies that can be used to test against. A way of specifying the dependencies is by adding them to the .pongo/pongorc file.

## .pongo and spec
both should be placed under <repository> directory.
becasuse the pongo spec files probably need to refer to some definitions or structures defined in plugin source code such as plugin schema definition.
if they're placed under subdirectory such as <repository>/tests (cd tests && bash -c "KONG_VERSION=... pongo run"),
subdirectory will be mounted under /kong-plugin of kong container, that means plugin source code is omitted, not mounted under any kong container directory.
so finally pongo spec files will report errors because they can't refer to variables or definitions defined in plugin source code.

## source code of custom plugins
source code be placed under <repository>/kong/plugins/<plugin-name>/*.lua.
otherwise, error occurs:
./spec/helpers.lua:...: error loading plugin schemas: on plugin '...': ... plugin is enabled but not installed;
no plugin found
