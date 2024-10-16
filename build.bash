#!/usr/bin/env bash

set -e

CYAN='\033[0;36m'
LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
CLEAR='\033[0m'

# builds a debian package
# usage: ./build.bash [--source]

if [[ $# -gt 1 ]] && [[ $1 != --source ]]; then
  echo >&2 "usage: $(basename "$0") [--source]"
  exit 1
fi

if ! command -v yq > /dev/null 2>&1; then
  echo >&2 "error: can not find yq in path!"
  exit 1
fi

if [[ ! -f godeb.yaml ]]; then
  echo >&2 "error: can't find godeb.yaml"
  exit 1
fi

for setting in project version; do
  if ! yq e -e ".${setting}" godeb.yaml > /dev/null 2>&1; then
    echo >&2 "error: missing key $setting in godeb.yaml"
    exit 1
  fi
done

echo -e "${YELLOW}Starting godeb build script${CLEAR}"

PROJECT="$(yq e .project godeb.yaml)"
export PROJECT

sdir="$(pwd)"
tdir="$(mktemp -d)"
bdir="$tdir/build"
mkdir -p "$bdir"

echo -e "${CYAN}Starting directory: $sdir${CLEAR}"
echo -e "${CYAN}Packaging directory: $bdir${CLEAR}"

echo -e "${LGREEN}Exporting git tree to packaging directory${CLEAR}"
(
  set -ex
  # export a pristine working tree
  git archive HEAD | tar -x -C "$bdir"
  git submodule update --init --recursive
  git submodule foreach --recursive \
    "git archive HEAD | tar -x -C $bdir/\$sm_path/"
)

echo -e "${LGREEN}Copying local modifications into the build directory${CLEAR}"
# copy local modifications into the final build
yq e '.localmods[]' < godeb.yaml | xargs -t -I'{}' cp -r '{}' "$bdir"

function yaml2cmd() {
  local key="$1"
  yq e ".${key}[]" < godeb.yaml | xargs -I'{}' bash -c "set -ex; {}"
}

function yaml2cmdwithdirs() {
  local key="$1"
  local sdir="$2"
  local bdir="$3"
  yq e ".${key}[]" < godeb.yaml | sed "s|\$bdir|$bdir|" |
    sed "s|\$sdir|$sdir|" | xargs -I'{}' bash -c "set -ex; {}"
}

echo -e "${LGREEN}Downloading dependencies${CLEAR}"
# do a fresh download of the dependencies
yaml2cmd dependencies

echo -e "${LGREEN}Running codegen steps${CLEAR}"
# run any necessary codegen steps
yaml2cmd codegen

# this function takes the path of a file (retrieved either from git ls-files
# or from a find on node_modules or vendor) and then creates the relevant entry
# for $PROJECT.install or $PROJECT.link
function create_sourcefile_install() {
  local d f p t bdir
  bdir="$2"
  f="$1"
  d="$(dirname "$f")"

  if [[ -L $f ]]; then
    # if the file is a symlink then add it and it's target to the symlinks
    # readlink resolves relative paths which we need to strip to build the
    # correct final path
    t="$(readlink "$f" | sed "s|^$(pwd)/||")"
    echo "$f /usr/src/$PROJECT/$t" >> "$bdir/debian/$PROJECT.links"
    return
  fi

  if [[ $d == . ]]; then
    p=""
  else
    p="$d"
  fi

  # sed "s|\$| /usr/src/$PROJECT/$p|" <<< "$f" >> \
  #   "$bdir/debian/$PROJECT.install"
  echo "$f /usr/src/$PROJECT/$p" >> "$bdir/debian/$PROJECT.install"
}

# this function takes the path of a file (retrieved from a find on the build
# directory) and created the relevant entries in $PROJECT.install
# we can't do something simple like just list the build directory in the
# install file because it will maintain the top-level "build" directory which
# we want to strip
# shellcheck disable=SC2317
function create_build_install() {
  local bp d f p s bdir
  bdir="$4"
  f="$1"
  bp="$2"
  s="$3"
  d="$(dirname "$f")"

  if [[ $d == "$s" ]]; then
    p=""
  else
    # p="$(sed "s|^$s/||" <<< "$d")"
    p="${d//${s}\//}"
  fi

  # sed "s|\$| /usr/share/$PROJECT/$p|" <<< "$f" \
  #   >> "$bdir/debian/$PROJECT.install"
  echo "$f $bp/$p" >> "$bdir/debian/$PROJECT.install"
}

export -f create_build_install

# if we pass --source option then bundle all source code and vendored
# dependencies into /usr/src/$PROJECT
if [[ $1 == --source ]]; then
  echo -e "${YELLOW}We're doing a full-source build!${CLEAR}"
  # I'm leaving this here in case it's useful in the future but we can't use
  # it as-is because it flattens the directory structure completely
  # git ls-files --recurse-submodules | sed 's|$| /usr/share/project/src|g' \
  #   >> "$bdir/debian/$PROJECT.install"

  for f in $(git ls-files --recurse-submodules); do
    create_sourcefile_install "$f" "$bdir"
  done

  {
    yq e '.dependencydirs[]' < godeb.yaml | xargs -t -I'{}' \
      echo "{} /usr/src/$PROJECT"

    yq e '.codegensource[]' godeb.yaml | xargs -I'{}' bash -c "ls {}" |
      xargs -t -I'{}' bash -c "echo \"{} /usr/src/$PROJECT/\$(dirname \"{}\")\""

    yq e '.codegensourcedirs[]' godeb.yaml | xargs -t -I'{}' bash -c \
      "echo \"{} /usr/src/$PROJECT/\$(dirname \"{}\")\""
  } >> "$bdir/debian/$PROJECT.install"

  # export -f create_sourcefile_install
  # find node_modules -exec bash -c \
  #   "create_sourcefile_install \"\$0\" \"$bdir\"" {} \;
  # find vendor -exec bash -c 'create_sourcefile_install "$0"' {} \;
fi

echo -e "${LGREEN}Doing the build...${CLEAR}"
# do the actual build
yaml2cmd build

echo -e "${LGREEN}Copying files into the packaging directory post-build${CLEAR}"
# copy the resulting files into the packing directory
yq e '.copyfiles[]' < godeb.yaml | xargs -t -I'{}' \
  bash -c "cp -r --parents {} \"$bdir\""
yq e '.buildinstalldirs[]' godeb.yaml | awk -F: '{printf("%s%c", $1, 0)}' |
  xargs -0 -t -I'{}' cp -r '{}' "$bdir"
yq e '.manpages[]' < godeb.yaml | xargs -t -I'{}' cp -r '{}' "$bdir"

cd "$bdir"

yq e '.manpages[]' < godeb.yaml |
  xargs -t -I'{}' find "{}" -type f |
  sort -nr >> "debian/$PROJECT.manpages"

# shellcheck disable=SC2317
function do_find_for_build_install() {
  local bdir="$3"
  find "$1" -type f -exec bash -c \
    "create_build_install \"\$0\" \"$2\" \"$1\" \"$bdir\"" {} \;
}

export -f do_find_for_build_install

# shellcheck disable=SC2016
yq e '.buildinstalldirs[]' godeb.yaml |
  awk -F: '{printf("%s%c%s%c", $1, 0, $2, 0)}' |
  xargs -t -0 -n 2 bash -c \
    "do_find_for_build_install \"\$1\" \"\$2\" \"$bdir\"" argv0

# fresh download of dependencies for source package (they should be cached)
if [[ $1 == --source ]]; then
  echo -e "${LGREEN}Running dependency commands for source build${CLEAR}"
  yaml2cmdwithdirs sourcedependencies "$sdir" "$bdir"
fi

echo -e "${LGREEN}Running post-build cleanup commands${CLEAR}"
# do any cleanup if necessary
yaml2cmd cleanup

if [[ -n $GOARCH ]]; then
  archcmd="-a$GOARCH"
fi

echo -e "${LGREEN}Handing off to debuild...${CLEAR}"
# --no-tgz-check is helpful if we provide a debian package number (e.g., -1)
# we don't do that but I'm keeping it around anyway
# shellcheck disable=SC2086
time (
  set -ex
  debuild --no-tgz-check --no-lintian -e CC -e GOARCH $archcmd \
    --no-pre-clean --no-sign
)

echo -e "${LGREEN}Running lintian on the result${CLEAR}"
# i have tried every invocation possible on lintian overrides to get it to
# ignore stuff in the /usr/src/$PROJECT directory and it. just. doesn't. work.
# so ignore the result of lintian but at least print the results out which are
# sometimes helpful (had me enable pie on the binary for example)
time (
  set -ex
  lintian --fail-on warning ../"${PROJECT}"*.deb || true
)

echo -e "${YELLOW}godeb finished, copying package back to start${CLEAR}"
# copy deb back to start directory so the upload-artifacts action picks it up
mv -v ../"${PROJECT}"*.deb "$sdir/"

exit 0
