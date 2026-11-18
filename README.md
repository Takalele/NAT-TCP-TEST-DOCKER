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

The example discovers both data links automatically and disables DHCPv4 and
DHCPv6 on both. It assigns the same static IPv4 and IPv6 subnets to each link.
Each link uses its own routing table, so the addresses can overlap without
changing management on `eth0`. Run `vrf_shell eth2` inside a VRF shell
to open a nested shell; `exit` returns to the previous context. Run
`ip vrf identify` to check the current context.

Containerlab's Docker `kind: linux` nodes run with the privileges needed
to create VRFs and attach processes to them. The Linux host needs VRF
kernel support and cgroup v2 with BPF support. For standalone Docker VRF
tests, use `--privileged` on a trusted lab host only.

## Node settings

Omit `env:` to use the defaults: the node discovers unconfigured data interfaces
(`eth1`, `eth2`, and so on) at startup and starts both DHCPv4 and DHCPv6 on each.
It leaves `eth0` untouched. Each `ethN` uses VRF `vrf_ethN` and routing table
`N+10`.

- `VRF_INTERFACES`: optional space-separated allowlist, such as `eth1 eth2`.
  Set it only to limit VRF setup to specific links instead of auto-discovery.
- `VRF_WAIT_SECONDS`: startup window for late Containerlab links; default 10 seconds.
- `VRF_DHCP` and `VRF_DHCP6`: global defaults for DHCPv4 and DHCPv6,
  respectively. Both default to `1` (enabled). Set `0` to disable a client.
- `VRF_DHCP_ETH1` and `VRF_DHCP6_ETH1`: override the respective default for
  `eth1`. Use the uppercase interface suffix for other data links, for example
  `VRF_DHCP6_ETH2` for `eth2`.
- `NAT_SERVICES`: `nat-server` starts `echo-server` (TCP 31415), `sleep-server`
  (TCP 27182), and `tcp_server` (TCP 12345) in `vrf_eth1`, when present. Set
  `NAT_SERVICES=0` to disable this. Start additional listeners with `vrf_shell`
  if needed. Run iperf servers explicitly in the desired VRF.

Provide a DHCP server for each enabled protocol on the corresponding link.
DHCPv4 installs its gateway in the VRF's routing table. DHCPv6 requests an
address (IA_NA), not a delegated prefix, and requires Linux 5.18 or newer.
IPv6 gateways come from Router Advertisements, not DHCPv6. Enabling DHCPv6
allows Router Advertisements on that link without disabling SLAAC. Neither
client changes container-wide DNS.
To adapt the static overlap example to use DHCP on both links, remove its
`env:` overrides and the address-setting `exec:` commands.

### Use static addresses on `eth2` only

In a topology using the defaults, add this under the Containerlab node. Both
DHCP clients stay enabled on `eth1`; only `eth2` uses static addresses.

```yaml
env:
  VRF_DHCP_ETH2: "0"
  VRF_DHCP6_ETH2: "0"
exec:
  - >-
    /bin/bash -ec '
    deadline=$(( SECONDS + 35 ));
    until link=$(ip -o link show dev eth2 2>/dev/null) && [[ $link == *" master vrf_eth2 "* ]]; do
      if (( SECONDS >= deadline )); then
        echo "Timed out waiting for eth2 to join vrf_eth2" >&2;
        exit 1;
      fi;
      sleep 0.2;
    done;
    ip -4 addr replace 192.0.2.2/24 dev eth2;
    ip -6 addr replace 2001:db8::2/64 dev eth2'
```

Containerlab can run `exec:` before the entrypoint attaches the link. Wait
for `eth2` to join `vrf_eth2` before assigning addresses, as the
[`nat-vrf-static` helper](examples/nat-vrf-static) does for both links.

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