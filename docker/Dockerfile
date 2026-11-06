FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
COPY tools/ci/ubuntu-packages.txt /tmp/ubuntu-packages.txt
RUN apt-get update \
    && apt-get install -y --no-install-recommends $(grep -v '^#' /tmp/ubuntu-packages.txt) \
    && rm -rf /var/lib/apt/lists/* /tmp/ubuntu-packages.txt

WORKDIR /workspace/EglantinePS5-docker-build
