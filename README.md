# godeb

I build [go](https://go.dev)-based services using arm64 and amd64 systems, but
then I deploy them to (usually) raspberry pis and I prefer that to happen via
debian packages. This script abstracts some of the common steps across my
projects to simplify that process.

## dependencies

You must have the [yq](https://github.com/mikefarah/yq) utility available and
in your path.

You also need to have `git` available, and preferably, configured with a name
and email address.

## usage

Create a file in your project `godeb.yaml` with the following contents:

```yaml
---
# REQUIRED: used for various file and directory names
project: myproj

# REQUIRED: command to run to get the current project version
version: jq -r .version package.json
```

### changelog

We don't care about making a real changelog (this is an internal project not
used for general consumption) however it's required for debian packaging so
we have a script that can generate a fake, real changelog entry.

```shell
./changelog.bash noble # or whatever debian/ubuntu distribution want
```
