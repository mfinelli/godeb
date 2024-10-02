#!/usr/bin/env bash

set -e

# tries to do initial debian packaging setup for a new project
# usage: ./init.bash

if [[ $# -ne 0 ]]; then
  echo >&2 "usage: $(basename "$0")"
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

if ! yq e -e ".project" godeb.yaml > /dev/null 2>&1; then
  echo >&2 "error: missing key project in godeb.yaml"
  exit 1
fi

project="$(yq e .project godeb.yaml)"
user="$(git config user.name)"
[[ -z $user ]] && user="$(whoami)"
email="$(git config user.email)"
[[ -z $email ]] && email="$(whoami)@$(hostname)"

url=""
desc="PUT YOUR DESCRIPTION HERE..."
if command -v gh > /dev/null 2>&1; then
  # if we have the github-cli then pull the description
  # (it automatically uses the current repo if it's configured)
  desc="$(gh repo view --json description | jq -r .description)"
  url="$(gh repo view --json url | jq -r .url)"
fi

if [[ -z $url ]]; then
  url="$(git remote -v | grep fetch | grep origin | awk '{print $2}' |
    sed 's|git@github.com:|https://github.com/|' | sed 's/.git$//')"
fi

mkdir -p debian/source
[[ ! -e debian/source/format ]] && echo "3.0 (native)" > debian/source/format

[[ ! -e debian/control ]] && cat << EOF > debian/control
Source: $project
Section: misc
Priority: optional
Maintainer: $user <$email>
Build-Depends: debhelper-compat (= 13)
Standards-Version: 4.7.0
Homepage: $url
Rules-Requires-Root: no

Package: $project
Architecture: arm64
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: $desc
EOF

[[ ! -e debian/copyright ]] && cat << EOF > debian/copyright
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $project
Upstream-Contact: $user <$email>
Source: $url

Files: *
Copyright: $(date '+%Y') $user <$email>
License: TODO: SPDX-IDENTIFIER

License: TODO: SPDX-IDENTIFIER
$(sed 's/^$/./' LICENSE | sed 's/^/ /')
EOF

[[ ! -e debian/$project.install ]] &&
  echo "README.md /usr/share/doc/$project" > "debian/$project.install"

[[ ! -e debian/rules ]] && cat << 'EOF' > debian/rules
#!/usr/bin/make -f

%:
        dh $@

        override_dh_shlibdeps:
                dh_shlibdeps -l/usr/aarch64-linux-gnu/lib
EOF

sed="sed"
if [[ $(uname) == Darwin ]]; then
  sed="gsed"
fi
$sed -i -e 's/        /\t/g' debian/rules
chmod +x debian/rules

exit 0
