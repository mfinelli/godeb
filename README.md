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

# OPTIONAL: locally modified files/directories to bring into the final build
localmods: []
  # - Makefile
  # - debian
  # - godeb.yaml

# OPTIONAL: commands to run to fetch dependencies
dependencies: []
  # - npm ci
  # - go mod vendor

# OPTIONAL: commands to run to fetch dependencies when doing a --source build
#           note in these commands both $sdir and $bdir are available
sourcedependencies: []
  # - npm ci --cpu arm64
  # - go mod vendor
  # - cp -r "$sdir/vendor" "$bdir"

# OPTIONAL: list of dependency directories to include when building with the
#           --source option
dependencydirs: []
  # - node_modules
  # - vendor

# OPTIONAL: any code generation steps that need to be run
codegen: []
  # - sqlc generate

# OPTIONAL: any generated source files that should be included in full-source
#           build (by default only third-party dependencies and files committed
#           to the git tree are included)
codegensource: []
  # - db/db.go
  # - db/models.go
  # - db/*.sql.go

# OPTIONAL: the above can only handle individual files (or file globs) for
#           directories use this
codegensourcedirs: []
  # - dist

# OPTIONAL: steps to run to build the project and any accompanying files
build: []
  # - CC="" GOARCH="" make all
  # - make completions
  # - rm project
  # - make all # build again for the desired arch

# OPTIONAL: files to copy into the packaging directory after the build
copyfiles: []
  # - project
  # - _project
  # - project.bash
  # - project.fish

# OPTIONAL: after the build install files in the specified directories to the
#           specified paths; note you should still manually specify individual,
#           known files in debian/$PROJECT.install
buildinstalldirs: []
  # - build:/usr/share/$PROJECT

# OPTIONAL: if specified the directories that we should use to find manpages
manpages: []
  # - man

# OPTIONAL: any additional steps to run after the build but before handing off
#           to debuild
cleanup: []
  # - rm some/extra/file
  # - touch some/other/file
  # - chmod 0644 not/executable
```

### changelog

We don't care about making a real changelog (this is an internal project not
used for general consumption) however it's required for debian packaging so
we have a script that can generate a fake, real changelog entry.

```shell
./changelog.bash noble # or whatever debian/ubuntu distribution want
```

### init

As an alternative to `debmake` this script will write out the default, most
necessary information for the debian package trying to set some sane defaults
where possible.

```shell
./init.bash
```

## github actions

You can use this repository's built-in Github action to simplify things.
Here's an example workflow:

```yaml
name: Package
on:
  push:
    branches: [master]
    tags: [v*]
  pull_request:
    branches: [master]

jobs:
  default:
   runs-on: ubuntu-24.04
   timeout-minutes: 30
   steps:
     # checkout the code and install main dependencies
     - uses: actions/checkout@v4
       with:
         submodules: true
     - uses: actions/setup-node@v4
       with:
         node-version: lts/*
     - uses: actions/setup-go@v5
       with:
         go-version: stable

      # install any other software that your build process may require:
      - uses: mfinelli/setup-imagemagick@v5

      # install necessary tools
      - run: sudo apt-get update
      - run: sudo apt-get upgrade -y
      - run: sudo apt-get install -y build-essential dh-make devscripts

      # install cross-compilation libraries (-buildmode=pie uses cgo)
      # https://dh1tw.de/2019/12/cross-compiling-golang-cgo-projects/
      - run: sudo apt-get install -y gcc-aarch64-linux-gnu libc6-dev-arm64-cross

      # if you want to sign the resulting.deb
      - uses: crazy-max/ghaction-import-gpg@v6
        with:
          gpg_private_key: ${{ secrets.GPG_PRIVATE_KEY }}
          passphrase: ${{ secrets.GPG_PASSPHRASE }}
      - run: sudo apt-get install -y debsigs

      # do the build
      - uses: mfinelli/godeb@v1
        with:
          cc: aarch64-linux-gnu-gcc
          goarch: arm64
          include-source: true   # (default is false)
          signing-key: ABCD1234
          update-changelog: true # if you do this then set localmods to include
                                 # debian/changelog in your godeb.yaml

      # upload the resulting package as a workflow artifact
      - uses: actions/upload-artifact@v4
        with:
          name: myproj
          path: project_*.deb
```

## docker

For local testing there is a sample docker file in this repository. You can
build the image locally and then run it passing your local working directory
as a volume and then running `build.bash`.

```shell
cd godeb
sudo docker built -t godeb .
cd ../project
sudo docker run --rm -it -v "$(pwd):/build" godeb build.bash
```

## package signing

If you setup package signing you'll want to follow the guide here:
https://blog.packagecloud.io/how-to-gpg-sign-and-verify-deb-packages-and-apt-repositories/
(under the section "Verifying GPG signatures of .deb package files") to setup
your keyrings and policy files.
