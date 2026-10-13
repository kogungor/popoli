#!/bin/zsh
# Writes catalog/index.json, the list Settings ▸ Catalog reads. Run it after adding or changing
# an extension in catalog/; CI checks that the committed list matches the files.
set -euo pipefail
cd "${0:A:h}/.."
./build.sh >/dev/null
build/Popoli.app/Contents/MacOS/Popoli --catalog-index catalog > catalog/index.json
echo "Wrote catalog/index.json ($(grep -c '"file"' catalog/index.json) extensions)"
