# Tablet Chord Server

documentation coming soon.

## Setup

copy `conf/conf.example.dart` to `conf/conf.dart` and edit the values to make sense for your installation

run with

```bash
$ dart bin/server.dart
```

setup reverse proxy with nginx like this:

```
# PUT THIS OUTSIDE A SERVER BLOCK
map $http_upgrade $connection_upgrade_keepalive {
	default upgrade;
	''      '';
}
```

```
	# THESE SHOULD GO INSIDE A SERVER BLOCK
	location /chords {
		return 302 https://lafayettecc.org/chords/;
	}
	location /chords/ {
		proxy_pass http://127.0.0.1:8082;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header Host $host;
		proxy_redirect default;

		# allow websocket
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "upgrade";
	}
```

NOTE: `/chords` should match whatever you specified as `serverDirectory` in `conf/conf.dart`

# PREVIOUS SHELF README -- not deleted yet

A server app built using [Shelf](https://pub.dev/packages/shelf),
configured to enable running with [Docker](https://www.docker.com/).

This sample code handles HTTP GET requests to `/` and `/echo/<message>`

# Running the sample

## Running with the Dart SDK

You can run the example with the [Dart SDK](https://dart.dev/get-dart)
like this:

```
$ dart run bin/server.dart
Server listening on port 8080
```

And then from a second terminal:

```
$ curl http://0.0.0.0:8080
Hello, World!
$ curl http://0.0.0.0:8080/echo/I_love_Dart
I_love_Dart
```

## Running with Docker

If you have [Docker Desktop](https://www.docker.com/get-started) installed, you
can build and run with the `docker` command:

```
$ docker build . -t myserver
$ docker run -it -p 8080:8080 myserver
Server listening on port 8080
```

And then from a second terminal:

```
$ curl http://0.0.0.0:8080
Hello, World!
$ curl http://0.0.0.0:8080/echo/I_love_Dart
I_love_Dart
```

You should see the logging printed in the first terminal:

```
2021-05-06T15:47:04.620417  0:00:00.000158 GET     [200] /
2021-05-06T15:47:08.392928  0:00:00.001216 GET     [200] /echo/I_love_Dart
```
