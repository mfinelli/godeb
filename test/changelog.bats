#!/usr/bin/env bats

setup() {
  cp test/changelog/godeb.yaml .
  mkdir -p debian
}

teardown() {
  rm -rf godeb.yaml
  rm -rf debian/changelog
}

@test "outputs the expected changelog content" {
  date() {
    command TZ=America/Los_Angeles date -d "2001-02-03 04:05:06"
  }
  export -f date

  gdate() {
    # command TZ=America/Los_Angeles gdate -d "2001-02-03 04:05:06"
    echo "Sat, 03 Feb 2001 04:05:06 -0800"
  }
  export -f gdate

  git() {
    if [ "$1" = "config" ]; then
      if [ "$2" = "user.name" ]; then
        echo "Joe Developer"
      else
        echo "joe@example.com"
      fi
    else
      command git "${@}"
    fi
  }
  export -f git

  run ./changelog.bash noble
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ "$(cat debian/changelog)" = "$(cat test/changelog/changelog)" ]

  unset date gdate git
}
