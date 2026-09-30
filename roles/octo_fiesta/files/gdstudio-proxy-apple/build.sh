#!/usr/bin/env sh
# Compiles the plugin into ./dist. Copy the three files from there into the config folder:
#   gdstudio-proxy.dll, Jint.dll, Acornima.dll
set -e
cd "$(dirname "$0")"
rm -rf dist
dotnet publish gdstudio-proxy.csproj -c Release -o dist
rm -f dist/*.pdb
ls dist
