FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    iproute2 \
    iputils-ping \
    jq \
    tcpdump \
    ethtool \
    linux-tools-common \
    linux-tools-generic \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/lib/linux-tools/$(ls /usr/lib/linux-tools/ | head -1)/bpftool /usr/local/bin/bpftool

LABEL maintainer="xdp-vlan-policy-filter"
LABEL description="Ubuntu 24.04 image for VLAN-aware eBPF/XDP packet filtering lab"

CMD ["sleep", "infinity"]
