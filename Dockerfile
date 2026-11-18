FROM alpine:3.23 AS upstream
RUN apk add --no-cache ca-certificates git
WORKDIR /src
RUN git init -q \
    && git fetch --depth=1 https://github.com/Takalele/NAT-TCP-test.git 08e37378eae87023a37e959f43769aee8bae476f \
    && git checkout --detach FETCH_HEAD

FROM upstream AS tcp-build
RUN apk add --no-cache build-base patch
COPY legacy/nat-tcp-endpoints.patch /tmp/nat-tcp-endpoints.patch
RUN patch -p1 < /tmp/nat-tcp-endpoints.patch \
    && make CFLAGS=-O2 \
    && mkdir -p /out \
    && install -m755 tcp-keepalive-test tcp-recv-test tcp-send-test /out/

FROM upstream AS server-build
RUN apk add --no-cache build-base cargo
RUN cargo build --locked --release --manifest-path echo-server/Cargo.toml \
    && cargo build --locked --release --manifest-path sleep-server/Cargo.toml \
    && mkdir -p /out \
    && install -m755 echo-server/target/release/echo-server sleep-server/target/release/sleep-server /out/

FROM alpine:3.23 AS scapy-build
RUN apk add --no-cache ca-certificates py3-pip python3 \
    && python3 -m venv --without-pip /opt/scapy \
    && python3 -m pip --python /opt/scapy install --no-cache-dir --only-binary=:all: scapy==2.7.0

FROM alpine:3.23 AS node-base
RUN apk add --no-cache \
    bash \
    bind-tools \
    ca-certificates \
    conntrack-tools \
    curl \
    ethtool \
    fping \
    iperf \
    iperf3 \
    iproute2 \
    iputils \
    libpcap \
    net-tools \
    netcat-openbsd \
    nmap-nping \
    python3 \
    tcpdump \
    tini
COPY --from=scapy-build /opt/scapy/ /opt/scapy/
ENV PATH="/opt/scapy/bin:${PATH}"
COPY --from=tcp-build /out/ /usr/local/bin/
COPY --chmod=755 legacy/sendtest legacy/recvtest legacy/tcp_client legacy/tcp_server /usr/local/bin/
COPY --chmod=644 legacy/nat-repeat.py /usr/local/bin/
COPY --chmod=755 scripts/nat-entrypoint scripts/vrf_shell /usr/local/bin/
COPY --chmod=755 scripts/vrf-udhcpc /usr/local/libexec/
COPY --chmod=644 scripts/bashrc /root/.bashrc
WORKDIR /root
ENTRYPOINT ["/usr/local/bin/nat-entrypoint"]
CMD ["sleep", "infinity"]

FROM node-base AS nat-client
ENV TYPE=client

FROM node-base AS nat-server
RUN apk add --no-cache libgcc
COPY --from=server-build /out/ /usr/local/bin/
ENV TYPE=server
