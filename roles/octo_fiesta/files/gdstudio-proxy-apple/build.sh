#!/usr/bin/env sh
# Compiles the plugin into ./dist as a single merged DLL: gdstudio-proxy.dll (merging Jint and Acornima via ILRepack)
set -e
cd "$(dirname "$0")"
rm -rf dist
dotnet publish gdstudio-proxy.csproj -c Release -o dist
rm -f dist/*.pdb
ls dist
