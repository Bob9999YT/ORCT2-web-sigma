# ORCT2-web

Tooling to build OpenRCT2 for use in your browser!

## Building

Building should be as simple as:

```
# Make sure you cloned recursively
git submodule update --init --recursive
# Build the image!
podman build -t orct2-web .
```

(or `docker build .` if you prefer :D)

## Running

Just run the image:

```
podman run -p 8080:8080 -it orct2-web
```

...And point your browser at [http://localhost:8080](http://localhost:8080)!
