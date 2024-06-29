#!/usr/bin/env bash

echo "Running server build..."
dart compile exe bin/server.dart -o bin/server
