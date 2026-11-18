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
docker exec clab-nat-vrf-client vrf_shell eth2 ping -6 -c 1 2001:db8::1
docker exec -it clab-nat-vrf-client vrf_shell eth1
```

The example uses static, overlapping IPv4 and IPv6 addresses on two separate
links. Each link uses its own routing table, so overlapping addresses work without
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
- `VRF_DHCP` and `VRF_DHCP6`: global defaults for DHCPv4 and DHCPv6,
  respectively. Both default to `1` (enabled). Set `0` to disable a client.
- `VRF_DHCP_ETH1` and `VRF_DHCP6_ETH1`: override the respective default for
  `eth1`. Use the uppercase interface suffix for other data links, for example
  `VRF_DHCP6_ETH2` for `eth2`.
- `NAT_SERVICES`: `nat-server` starts `echo-server` (TCP 31415), `sleep-server`
  (TCP 27182), and `tcp_server` (TCP 12345) in `vrf_eth1`, when present. Set
  `NAT_SERVICES=0` to disable this. Start additional listeners with `vrf_shell`
  if needed. Run iperf servers explicitly in the desired VRF.

### Configure DHCP per link

Set the variables under the Containerlab node's `env:`. For example, run only
DHCPv4 on `eth1`, only DHCPv6 on `eth2`, and neither on other links:

```yaml
env:
  VRF_INTERFACES: "eth1 eth2"
  VRF_DHCP: "0"
  VRF_DHCP6: "0"
  VRF_DHCP_ETH1: "1"
  VRF_DHCP6_ETH2: "1"
```

Provide a DHCP server for each enabled protocol on the corresponding link.
DHCPv4 installs its gateway in the VRF's routing table. DHCPv6 requests an
address (IA_NA), not a delegated prefix, and requires Linux 5.18 or newer.
IPv6 gateways come from Router Advertisements, not DHCPv6. Enabling DHCPv6
allows Router Advertisements on that link without disabling SLAAC. Neither
client changes container-wide DNS.
When adapting the static example, remove its address-setting `exec` commands
for nodes you want to configure via DHCP.

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