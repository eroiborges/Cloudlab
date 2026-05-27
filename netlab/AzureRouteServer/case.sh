export rgnameaz="rg-vxlanlab"
export location="centralus" 
export vmsize="standard_b2ms" #"Standard_B4ms" #"Standard_D2ads_v5" #"Standard_D2s_v5"
export az_vnetname="lab-azvnet"

az group create --name $rgnameaz --location $location

for i in 140 150 160 161; do

  az network nsg create --resource-group $rgnameaz --name "nsg-azhosts"$i --location $location
  az network vnet create --resource-group $rgnameaz --name $az_vnetname$i --address-prefixes 10.$i.0.0/20 --subnet-name azhosts --subnet-prefixes 10.$i.0.0/26 --location $location --network-security-group "nsg-azhosts"$i
  
  case $i in
    140|150)
      # Extra command for 140 and 150
      az network vnet subnet create --name fw_untrust --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.128/27
      sleep 5
      az network vnet subnet create --name fw_trust --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.160/27
      
  esac  

done

export hub_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"150" -o tsv --query id)
export spoke140_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"140" -o tsv --query id)
export spoke160_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"160" -o tsv --query id)
export spoke161_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"161" -o tsv --query id)


az network vnet peering create -g $rgnameaz -n vnetpeer160 --vnet-name $az_vnetname"150" --remote-vnet $spoke160_vnetnameid --allow-vnet-access 
az network vnet peering create -g $rgnameaz -n vnetpeer161 --vnet-name $az_vnetname"150" --remote-vnet $spoke161_vnetnameid --allow-vnet-access 
az network vnet peering create -g $rgnameaz -n vnetpeer140 --vnet-name $az_vnetname"150" --remote-vnet $spoke140_vnetnameid --allow-vnet-access --allow-forwarded-traffic
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"160" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"161" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"140" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic


# update NSG to allow  SSH
export myip=$(curl -s -k ifconfig.me)
az network nsg rule create --resource-group $rgnameaz --nsg-name "nsg-azhosts150" --name "Allow-SSH" --protocol Tcp --direction Inbound --priority 1001 --source-address-prefixes "$myip" --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow

# VM Jumpbox
az network nic create --name "nic-jumpbox" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"150" \
--ip-forwarding false --private-ip-address 10.150.0.20 --private-ip-address-version IPv4  

az network public-ip create --resource-group $rgnameaz --name "pip-jumpbox" --location $location --allocation-method Static --sku Standard
az network nic ip-config update --name "ipconfig1" --nic-name "nic-jumpbox" --resource-group $rgnameaz --public-ip-address "pip-jumpbox" 

az vm create --resource-group $rgnameaz --name "vm-jumpbox-01" --image Ubuntu2204 --size $vmsize --nics "nic-jumpbox" --admin-username sadmin --generate-ssh-keys --no-wait

# VM Firewall 140 IP Forwarding NICs
az network nic create --name "nic-fw-untrust" --resource-group $rgnameaz --location $location --subnet fw_untrust --vnet-name $az_vnetname"140" \
--ip-forwarding true --private-ip-address 10.140.0.132 --private-ip-address-version IPv4 
az network nic create --name "nic-fw-trust" --resource-group $rgnameaz --location $location --subnet fw_trust --vnet-name $az_vnetname"140" \
--ip-forwarding true --private-ip-address 10.140.0.164 --private-ip-address-version IPv4 

# VM Firewall 140
az vm create --resource-group $rgnameaz --name "vm-firewall140-01" --image Ubuntu2204 --size $vmsize --nics "nic-fw-untrust" "nic-fw-trust" --admin-username sadmin --generate-ssh-keys --no-wait

# VM Firewall 150 IP Forwarding NICs
az network nic create --name "nic-fw150-untrust" --resource-group $rgnameaz --location $location --subnet fw_untrust --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.132 --private-ip-address-version IPv4 
az network nic create --name "nic-fw150-trust" --resource-group $rgnameaz --location $location --subnet fw_trust --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.164 --private-ip-address-version IPv4 

# VM Firewall 150
az vm create --resource-group $rgnameaz --name "vm-firewall150-01" --image Ubuntu2204 --size $vmsize --nics "nic-fw150-untrust" "nic-fw150-trust" --admin-username sadmin --generate-ssh-keys --no-wait


# criar azure route table para FW140 e FW150
az network route-table create --name 'rt-fw140-trust' --resource-group $rgnameaz --location $location --disable-bgp-route-propagation true
az network route-table create --name 'rt-fw150-trust' --resource-group $rgnameaz --location $location --disable-bgp-route-propagation true
# associar route table na subnet azhosts
az network vnet subnet update --vnet-name $az_vnetname"140" --name fw_trust --resource-group $rgnameaz --route-table 'rt-fw140-trust'
az network vnet subnet update --vnet-name $az_vnetname"150" --name fw_trust --resource-group $rgnameaz --route-table 'rt-fw150-trust'

## executar dentro das VMs de FW:

sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf



sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null <<EOF
network:
  config: disabled
EOF

## Editar o arquivo /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
## adicionar o ip statico na interface ETH1
## adicionar rotas estaticas conforme topologia   FW140 Trust <> FW150 Trust 

VNET140:
fw_untrust: 10.140.0.128/27
fw_trust: 10.140.0.160/27

VNET150:
fw_untrust: 10.150.0.128/27
fw_trust: 10.150.0.160/27


FW140
eth0: 10.140.0.132/27
gateway4: 10.140.0.129

routes:
  - to: 10.140.0.128/27
    via: 10.140.0.129
    metric: 200
  - to: 0.0.0.0/0
    via: 10.140.0.129
    metric: 200

eth1: 10.140.0.164/27
gateway4: 10.140.0.161

dhcp4: no
addresses: [10.140.0.164/27]
routes:
  - to: 10.150.0.160/27
    via: 10.140.0.161
    metric: 200


    10.150.0.164


FW150
eth0: 10.150.0.132/27
gateway4: 10.150.0.129

routes:
  - to: 10.150.0.128/27
    via: 10.150.0.129
    metric: 200
  - to: 0.0.0.0/0
    via: 10.150.0.129
    metric: 200

eth1: 10.150.0.164/27
gateway4: 10.150.0.161
routes:
  - to: 10.140.0.160/27
    via: 10.150.0.161
    metric: 200

#### ROUTE SERVER AZURE
#### SETUP

## route server
subnetId=$(az network vnet subnet show --name 'RouteServerSubnet' --resource-group $rgnameaz --vnet-name $az_vnetname"140" --query id -o tsv)

# Create a Standard public IP for Route Server
az network public-ip create --resource-group $rgnameaz --name 'RouteServerIP' --sku Standard --version 'IPv4'

# Create the Route Server
az network routeserver create --name 'demoars' --resource-group $rgnameaz --hosted-subnet $subnetId --public-ip-address 'RouteServerIP'

# Get Route Server details for NVA configuration
az network routeserver show --resource-group $rgnameaz --name 'demoars'   --query '{id:id, provisioningState:provisioningState, hostedSubnet:hostedSubnet, virtualRouterIps:virtualRouterIps, virtualRouterAsn:virtualRouterAsn}' -o json


# Create BGP peering with the network virtual appliance
az network routeserver peering create --name 'firewall' --peer-ip '10.140.0.164' --peer-asn '65001' --routeserver 'demoars' --resource-group $rgnameaz
az network routeserver peering create --name 'firewall150' --peer-ip '10.150.0.164' --peer-asn '65002' --routeserver 'demoars' --resource-group $rgnameaz

router bgp 65001
  neighbor 10.140.0.68 remote-as 65515
  neighbor 10.140.0.68 ebgp-multihop 2
  neighbor 10.140.0.69 remote-as 65515
  neighbor 10.140.0.69 ebgp-multihop 2
  address-family ipv4 unicast
    neighbor 10.140.0.68 activate
    neighbor 10.140.0.68 route-map PERMIT-ALL out
    neighbor 10.140.0.68 route-map PERMIT-ALL in
    neighbor 10.140.0.69 activate
    neighbor 10.140.0.69 route-map PERMIT-ALL out
    neighbor 10.140.0.69 route-map PERMIT-ALL in
    network 192.168.0.0/16


## cliente Remote
az network nic create --name "nic-remote01" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name vnetremote \
 --private-ip-address 192.168.0.8 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-remote01" --image Ubuntu2204 --size $vmsize --nics "nic-remote01" --admin-username sadmin --generate-ssh-keys --no-wait

## VM Cliente on VNET 161
az network nic create --name "nic-cliente01" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"161" \
 --private-ip-address 10.161.0.8 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-cliente01" --image Ubuntu2204 --size $vmsize --nics "nic-cliente01" --admin-username sadmin --generate-ssh-keys --no-wait


# criar azure route table para remote01 e cliente01
az network route-table create --name 'rt-remote' --resource-group $rgnameaz --location $location --disable-bgp-route-propagation true
az network route-table create --name 'rt-cliente01' --resource-group $rgnameaz --location $location --disable-bgp-route-propagation true

# criar rota estatica na route table para remote01
az network route-table route create --resource-group $rgnameaz --route-table-name 'rt-remote' --name 'to-azhosts161' --address-prefix 10.161.0.0/24 --next-hop-type VirtualAppliance --next-hop-ip-address 10.140.0.164
# criar rota estatica na route table para cliente01
az network route-table route create --resource-group $rgnameaz --route-table-name 'rt-cliente01' --name 'to-remote192' --address-prefix 192.168.0.0/24 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.164  

# associar route table na subnet azhosts
az network vnet subnet update --vnet-name vnetremote --name azhosts --resource-group $rgnameaz --route-table 'rt-remote'
az network vnet subnet update --vnet-name $az_vnetname"161" --name azhosts --resource-group $rgnameaz --route-table 'rt-cliente01'