#!/usr/bin/env bash

#/usr/bin/dart bin/server.dart >> debug.log 2>&1

if [ -f bin/server ]
then
	echo "Running pre-built binary... if this is out of date, delete bin/server or manually run build.sh"
	./bin/server
else
	echo "Server binary not found, running build first"
	./build.sh
	
	if [ -f bin/server ]
	then
		./bin/server
	else
		echo "Server build failed... attempting to run from dart file"
		/usr/bin/dart bin/server.dart
	fi
fi
