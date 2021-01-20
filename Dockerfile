FROM debian:sid-slim AS builder
ENV NODEJS_MAJOR=14

ARG DEBIAN_FRONTEND=noninteractive
LABEL MAINTAINER="kmahyyg <spam@kmahyyg.xyz>"

# BUILD ZTNCUI IN FIRST STAGE
WORKDIR /build
RUN apt update -y && \
    apt install curl gnupg2 ca-certificates zip unzip build-essential git --no-install-recommends -y && \
    curl -sL -o node_lts.sh https://deb.nodesource.com/setup_lts.x && \
    bash node_lts.sh && \
    apt install -y nodejs --no-install-recommends && \
    rm -f node_lts.sh && \
    git clone https://github.com/key-networks/ztncui && \
    npm install -g node-gyp pkg && \
    cd ztncui/src && \
    npm install && \
    pkg -c ./package.json -t "node${NODEJS_MAJOR}-linux-x64" bin/www -o ztncui && \
    zip -r /build/artifact.zip ztncui node_modules/argon2/build/Release

# BUILD GO UTILS
FROM golang:buster AS argong
WORKDIR /buildsrc
COPY argon2g.go .
RUN mkdir -p binaries && \
    go get -u golang.org/x/crypto/argon2 && \
    go build -ldflags='-s -w' -trimpath -o binaries/argon2g ./argon2g.go && \
    git clone https://github.com/jsha/minica && \
    cd minica && \
    go mod download && \
    go build -ldflags='-s -w' -trimpath -o ../binaries/minica && \
    cd ../ && \
    git clone https://github.com/tianon/gosu && \
    cd gosu && \
    go mod download && \
    go build -o ../binaries/gosu -ldflags='-s -w' -trimpath


# START RUNNER
FROM debian:sid-slim AS runner
RUN apt update -y && \
    apt install curl gnupg2 ca-certificates unzip supervisor --no-install-recommends -y && \
    curl -sL -o ztone.sh https://install.zerotier.com && \
    bash ztone.sh && \
    rm -f ztone.sh && \
    apt clean -y && \
    rm -rf /var/lib/zerotier-one && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/key-networks/ztncui
COPY --from=builder /build/artifact.zip .
RUN unzip ./artifact.zip && \
    rm -f ./artifact.zip

COPY --from=argong /buildsrc/binaries/gosu /bin/gosu
COPY --from=argong /buildsrc/binaries/minica /usr/local/bin/minica
COPY --from=argong /buildsrc/binaries/argon2g /usr/local/bin/argon2g
COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 3000
EXPOSE 9993

VOLUME ["/opt/key-networks/ztncui/etc"]
VOLUME [ "/var/lib/zerotier-one" ]
ENTRYPOINT [ "/entrypoint.sh" ]