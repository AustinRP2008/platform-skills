#!/bin/sh
# Runs inside the build container as root. Debian/Ubuntu bases.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
# shellcheck disable=SC2086 # PACKAGES is a space-separated list on purpose
apt-get -y install --no-install-recommends $PACKAGES
groupadd --gid 10001 app
useradd --uid 10001 --gid 10001 --create-home --home-dir /home/app --shell /usr/sbin/nologin app
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/* /var/tmp/*
