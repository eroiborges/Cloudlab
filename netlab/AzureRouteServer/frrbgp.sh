

#Instalação e habilitação do FRR (com BGP)
sudo apt update
sudo apt install frr frr-pythontools -y
sudo systemctl enable frr
sudo systemctl start frr

# Habilitar BGP no FRR
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
sleep 5

# Ativar IP forwarding
sysctl -w net.ipv4.ip_forward=1
sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

#Router 1 (AS 65001)
sudo vtysh << EOF
configure terminal
!
route-map PERMIT-ALL permit 10
!
router bgp 65001
 bgp router-id 10.150.0.10
 neighbor 10.150.0.12 remote-as 65002
 !
 address-family ipv4 unicast
  neighbor 10.150.0.12 activate
  neighbor 10.150.0.12 route-map PERMIT-ALL in
  neighbor 10.150.0.12 route-map PERMIT-ALL out
  network 10.10.10.0/24
  network 10.150.2.0/25
 exit-address-family
exit
end
write memory
EOF

#Router 2 (AS 65002)
sudo vtysh << EOF
configure terminal
!
route-map PERMIT-ALL permit 10
!
router bgp 65002
 bgp router-id 10.150.0.12
 neighbor 10.150.0.10 remote-as 65001
 neighbor 10.160.0.4 remote-as 65003
 neighbor 10.160.0.4 ebgp-multihop 2
 !
 address-family ipv4 unicast
  neighbor 10.150.0.10 activate
  neighbor 10.150.0.10 route-map PERMIT-ALL in
  neighbor 10.150.0.10 route-map PERMIT-ALL out
  neighbor 10.160.0.4 activate
  neighbor 10.160.0.4 route-map PERMIT-ALL in
  neighbor 10.160.0.4 route-map PERMIT-ALL out
  network 10.20.10.0/24
  network 10.150.2.128/25
 exit-address-family
exit
end
write memory
EOF

#Router 3 (AS 65003)
sudo vtysh << EOF
configure terminal
!
route-map PERMIT-ALL permit 10
!
router bgp 65003
 bgp router-id 10.160.0.4
 neighbor 10.150.0.12 remote-as 65002
 neighbor 10.150.0.12 ebgp-multihop 2
 !
 address-family ipv4 unicast
  neighbor 10.150.0.12 activate
  neighbor 10.150.0.12 route-map PERMIT-ALL in
  neighbor 10.150.0.12 route-map PERMIT-ALL out
  network 10.160.0.0/26
 exit-address-family
exit
end
write memory
EOF

# Rotas estáticas para garantir NHT (Next Hop Tracking)
# No Router 2
sudo ip route add 10.160.0.4 via 10.150.0.1

# No Router 3
sudo ip route add 10.150.0.12 via 10.160.0.1

# Validação
show ip bgp summary
show ip bgp
show ip bgp neighbors <neighbor-IP> advertised-routes
ip route show


#Router 4 (AS 65004)
sudo vtysh << EOF
configure terminal
!
route-map PERMIT-ALL permit 10
!
router bgp 65004
 bgp router-id 192.168.100.2
 neighbor 192.168.100.1 remote-as 65001
 !
 address-family ipv4 unicast
  neighbor 192.168.100.1 activate
  neighbor 192.168.100.1 route-map PERMIT-ALL in
  neighbor 192.168.100.1 route-map PERMIT-ALL out
  network 10.161.0.0/26
 exit-address-family
exit
end
write memory
EOF


# Router 1
ip link add vxlan100 type vxlan id 100 dev eth0 remote 10.150.0.164 dstport 4789
ip addr add 192.168.100.1/30 dev vxlan100
ip link set vxlan100 up

/etc/netplan/99-router1.yaml

network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [10.150.0.10/26]
      gateway4: 10.150.0.1
  tunnels:
    vxlan100:
      mode: vxlan
      id: 100
      link: eth0
      remote: 10.150.0.164
      local: 10.150.0.10
      port: 4789
      addresses: [192.168.100.1/30]


# Router 4
ip link add vxlan100 type vxlan id 100 dev eth0 remote 10.150.2.4 dstport 4789
ip addr add 192.168.100.2/30 dev vxlan100
ip link set vxlan100 up

/etc/netplan/99-router4.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [10.150.2.4/25]
      gateway4: 10.161.0.1
  tunnels:
    vxlan100:
      mode: vxlan
      id: 100
      link: eth0
      remote: 10.150.0.10
      local: 10.150.2.4
      port: 4789
      addresses: [192.168.100.2/30]



# Rotas estáticas para garantir NHT (Next Hop Tracking)
# No Router 1
sudo ip route add 10.161.0.4 via 10.150.0.1

# No Router 4
sudo ip route add 10.150.0.10 via 10.161.0.1


configure terminal
!
route-map SET-NEXTHOP permit 10
 set ip next-hop 10.150.0.164
!
router bgp 65001
 bgp router-id 10.150.0.10
 neighbor 192.168.100.2 remote-as 65002
 !
 address-family ipv4 unicast
  neighbor 192.168.100.2 activate
  neighbor 192.168.100.2 route-map SET-NEXTHOP out
  neighbor 192.168.100.2 route-map PERMIT-ALL out
  neighbor 192.168.100.2 route-map PERMIT-ALL in
  network 10.10.10.0/24
  network 10.150.2.0/25
 exit-address-family
exit
end

neighbor 192.168.100.2 next-hop-self


  "virtualRouterAsn": 65515,
  "virtualRouterIps": [
    "10.150.3.5",
    "10.150.3.4"


    neighbor 10.150.3.5 remote-as 65515

router bgp 65002
  neighbor 10.150.3.4 remote-as 65515
  neighbor 10.150.3.4 ebgp-multihop 2
  address-family ipv4 unicast
    neighbor 10.150.3.4 activate
    neighbor 10.150.3.4 route-map PERMIT-ALL out
    neighbor 10.150.3.4 route-map PERMIT-ALL in
  
  neighbor 10.150.3.5 remote-as 65515
  neighbor 10.150.3.5 ebgp-multihop 2
    address-family ipv4 unicast
    neighbor 10.150.3.5 activate
    neighbor 10.150.3.5 route-map PERMIT-ALL out
    neighbor 10.150.3.5 route-map PERMIT-ALL in


az network routeserver peering show  --resource-group $rgnameaz --name 'firewall' --routeserver 'demoars' -o json
az network routeserver peering list-learned-routes --resource-group $rgnameaz --name 'firewall' --routeserver 'demoars'  -o json
az network routeserver peering list-advertised-routes  --resource-group $rgnameaz --name 'firewall' --routeserver 'demoars'  -o json

ip prefix-list REDES_PROPAGAR seq 5 permit 10.10.10.0/24
ip prefix-list REDES_PROPAGAR seq 10 permit 10.150.2.0/25

ip prefix-list REDES_NOADVERTISE seq 5 permit 10.20.20.0/24

route-map EXPORT-BGP permit 10
  match ip address prefix-list REDES_PROPAGAR
  set ip next-hop 10.150.0.164

route-map EXPORT-BGP permit 20
  match ip address prefix-list REDES_NOADVERTISE
  set ip next-hop 10.150.0.164
  set community 65535:65282

route-map EXPORT-BGP permit 100
  # catch-all: propaga outras rotas normalmente (ou pode negar)

router bgp 65002
 address-family ipv4 unicast
  neighbor 10.150.3.4 activate
  neighbor 10.150.3.4 route-map EXPORT-BGP out
  neighbor 10.150.3.5 activate
  neighbor 10.150.3.5 route-map EXPORT-BGP out

# REDES_PROPAGAR: só essas rotas são propagadas com next-hop forçado.
# REDES_NOADVERTISE: essas rotas são propagadas com next-hop forçado e community no-advertise (não serão repassadas pelo Route Server).
# catch-all: outras rotas (não casadas acima) podem ser propagadas normalmente ou você pode negar (usando route-map EXPORT-BGP deny 100).
