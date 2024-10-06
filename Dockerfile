FROM mfinelli/imagemagick:latest AS imagemagick

FROM ubuntu:24.04
WORKDIR /build

RUN \
  apt update -y && \
  apt install -y \
  curl \
  dh-make \
  devscripts \
  grep \
  jq \
  less \
  libarchive-tools \
  vim \
  wget

# keep this list in-sync with docker-imagemagick dockerfile
RUN \
  apt-get install -y \
  libjbig0 \
  libtiff6 \
  libraqm0 \
  libdjvulibre21 \
  libfontconfig1 \
  libwebpmux3 \
  libwebpdemux2 \
  libopenexr-3-1-30 \
  libgomp1

COPY .go-version /build

RUN \
  gomod="$(cat .go-version)" && \
  golang="$(curl -s 'https://go.dev/dl/?mode=json' | jq -r '.[].version' | \
    grep "$gomod")" && \
  case "$(dpkg --print-architecture)" in \
    amd64) \
      wget -nv https://go.dev/dl/$golang.linux-amd64.tar.gz && \
      tar -C /usr/local -xzf $golang.linux-amd64.tar.gz && \
      rm $golang.linux-amd64.tar.gz \
      ;; \
    arm64) \
      wget -nv https://go.dev/dl/$golang.linux-arm64.tar.gz && \
      tar -C /usr/local -xzf $golang.linux-arm64.tar.gz && \
      rm $golang.linux-arm64.tar.gz \
      ;; \
  esac

RUN \
  nodejs_lts="$(curl -s https://nodejs.org/download/release/index.json | \
    jq -r '.[] | select(.lts) | .version' | head -n1)" && \
  case "$(dpkg --print-architecture)" in \
    amd64) \
      wget -nv https://nodejs.org/dist/$nodejs_lts/node-$nodejs_lts-linux-x64.tar.xz && \
      tar Jxf node-$nodejs_lts-linux-x64.tar.xz -C /usr/local --strip-components 1 && \
      rm node-$nodejs_lts-linux-x64.tar.xz \
      ;; \
    arm64) \
      wget -nv https://nodejs.org/dist/$nodejs_lts/node-$nodejs_lts-linux-arm64.tar.xz && \
      tar Jxf node-$nodejs_lts-linux-arm64.tar.xz -C /usr/local --strip-components 1 && \
      rm node-$nodejs_lts-linux-arm64.tar.xz \
      ;; \
  esac

COPY --from=imagemagick /usr/bin/magick /usr/local/bin

RUN \
  rm .go-version && \
  mkdir /godeb
COPY ./*.bash ./Makefile README.md /godeb
RUN \
  cd /godeb && \
  make install && \
  cd && \
  rm -rf /godeb

ENV PATH="$PATH:/usr/local/go/bin"
