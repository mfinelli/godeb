#!/usr/bin/env bash

set -e

# update the debian/changelog with the current version and date
# usage: ./changelog.bash distribution
# example: ./changelog.bash noble

if [[ $# -ne 1 ]]; then
  echo >&2 "usage: $(basename "$0") distribution"
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

if [[ ! -d debian ]]; then
  echo >&2 "error: can't find debian directory"
  exit 1
fi

for setting in project version; do
  if ! yq e -e ".${setting}" godeb.yaml > /dev/null 2>&1; then
    echo >&2 "error: missing key $setting in godeb.yaml"
    exit 1
  fi
done

date="date"

if [[ $(uname) == Darwin ]]; then
  if ! command -v gdate > /dev/null 2>&1; then
    echo >&2 "error: you must install gnu coreutils"
    exit 1
  fi

  date="gdate"
fi

shortname="$1"
project="$(yq e .project godeb.yaml)"
versioncmd="$(yq e .version godeb.yaml)"
version="$($versioncmd)"
header="$project ($version) $shortname; urgency=medium"
echo "$header" > debian/changelog
echo >> debian/changelog

subject=""
msg=""
if git show-ref --tags "$version" --quiet; then
  subject="$(git tag -l --format='%(contents:subject)' "$version")"
  msg="$(git tag -l --format='%(contents:body)' "$version")"
  [[ -z $subject && -z $msg ]] && subject="Release version $version"
elif git show-ref --tags "v$version" --quiet; then
  subject="$(git tag -l --format='%(contents:subject)' "v$version")"
  msg="$(git tag -l --format='%(contents:body)' "v$version")"
  [[ -z $subject && -z $msg ]] && subject="Release version $version"
else
  subject="Release version $version"
  msg=""
fi

body=""
if [[ -z $msg ]]; then
  body="  * $subject"
else
  # shellcheck disable=SC2001
  body="$(sed 's/^/  /' <<< "$msg")"
fi

{
  echo -n "$body"
  echo
  echo
} >> debian/changelog

cdate="$($date -R)"
user="$(git config user.name)"
[[ -z $user ]] && user="$(whoami)"
email="$(git config user.email)"
[[ -z $email ]] && email="$(whoami)@$(hostname)"
footer=" -- $user <$email>  $cdate"
echo "$footer" >> debian/changelog

exit 0
