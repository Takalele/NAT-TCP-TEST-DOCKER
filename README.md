# NAT-TCP-TEST-DOCKER

Alpine-based NAT test nodes for Containerlab. Both images include iperf 2
(`iperf`), iperf 3 (`iperf3`), tcpdump, iproute2, ping, fping, dig, curl,
ethtool, conntrack, netcat, Scapy and the NAT-TCP client tools. Nping
(`nping`) replaces `hping3`; its command-line options differ.

## Build and start the example

```sh
docker build --target nat-client -t nat-client:latest .
docker build --target nat-server -t nat-server:latest .
sudo containerlab deploy -t examples/nat-vrf.clab.yml
docker exec clab-nat-vrf-client vrf_shell eth1 ping -c 1 192.0.2.1
docker exec clab-nat-vrf-client vrf_shell eth2 ping -c 1 192.0.2.1
docker exec -it clab-nat-vrf-client vrf_shell eth1
```

The example assigns the same IPv4 addresses on two separate links. Each
link uses its own routing table, so overlapping addresses work without
changing management on `eth0`. Run `vrf_shell eth2` inside a VRF shell
to open a nested shell; `exit` returns to the previous context. Run
`ip vrf identify` to check the current context.

Containerlab's Docker `kind: linux` nodes run with the privileges needed
to create VRFs and attach processes to them. The Linux host needs VRF
kernel support and cgroup v2 with BPF support. For standalone Docker VRF
tests, use `--privileged` on a trusted lab host only.

## Node settings

- `VRF_INTERFACES`: space-separated data interfaces, such as `eth1 eth2`.
  If omitted, discover unconfigured `ethN` data interfaces at startup.
  `eth0` is never enrolled. `ethN` uses VRF `vrf_ethN` and table `N+10`.
- `VRF_WAIT_SECONDS`: discovery window for late Containerlab links; default 10.
- `VRF_DHCP`: defaults to `1`. A lease sets IPv4 addresses and gateway routes
  on that VRF only; it does not replace container-wide DNS. Set `0` for static IPs.
- `NAT_SERVICES`: `nat-server` starts `echo-server` (TCP 31415), `sleep-server`
  (TCP 27182), and `tcp_server` (TCP 12345) in `vrf_eth1`, when present. Set
  `NAT_SERVICES=0` to disable this. Start additional listeners with `vrf_shell`
  if needed. Run iperf servers explicitly in the desired VRF.

## TCP test tools

The upstream [NAT-TCP-test](https://github.com/Takalele/NAT-TCP-test) tools
are built from a pinned commit. Pass your lab server IP explicitly to
`tcp-send-test`, `tcp-recv-test`, and `tcp-keepalive-test`. The compiled default
is loopback, not the upstream public server. `tcp-recv-test` uses `sleep-server`.
`sendtest` and `recvtest` require a target and default to one run. Use
`tcp_client` and `tcp_server` for shorter TCP lifecycle checks. The server
defaults to reset mode and uses the kernel's TCP reset instead of sending a
crafted packet. Use `tcp_server --mode normal` for an echo and graceful close.

```sh
docker exec clab-nat-vrf-client vrf_shell eth1 tcp_client -s 192.0.2.1 immediate-reset
sudo containerlab destroy -t examples/nat-vrf.clab.yml --cleanup
```