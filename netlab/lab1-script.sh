## Variaveis

export rgnameaz="rg-azvnetlab"
export location="eastus2" 
export vmsize="standard_b4ms" #"Standard_B2ms" #"Standard_D2ads_v5" #"Standard_D2s_v5"
export az_vnetname="lab-azvnet"
export resourcename=$(tr -dc a-z0-9 </dev/urandom | head -c 13; echo)

## Resource group
az group create --name $rgnameaz --location $location

## Virtual Network

## 140 Onpremises
## 150 Azure Hub and 160 Spoke

for i in 140 150 160 161; do

  az network nsg create --resource-group $rgnameaz --name "nsg-azhosts"$i --location $location
  az network vnet create --resource-group $rgnameaz --name $az_vnetname$i --address-prefixes 10.$i.0.0/20 --subnet-name azhosts --subnet-prefixes 10.$i.0.0/26 --location $location --network-security-group "nsg-azhosts"$i
  
  case $i in
    140|150)
      # Extra command for 140 and 150
      az network vnet subnet create --name gatewaysubnet --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.64/26
      ;;
  esac

  case $i in
    150)
      # Firewall subnets for Hub150
      az network vnet subnet create --name fw_untrust --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.128/27
      sleep 5
      az network vnet subnet create --name fw_trust --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.160/27
      sleep 5
      az network vnet subnet create --name backend --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.192/27
      sleep 5
      az network vnet subnet create --name AzureBastionSubnet --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefix 10.150.1.0/26
      ;;
  esac

done

export hub_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"150" -o tsv --query id)
export spoke160_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"160" -o tsv --query id)
export spoke161_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"161" -o tsv --query id)

az network vnet peering create -g $rgnameaz -n vnetpeer160 --vnet-name $az_vnetname"150" --remote-vnet $spoke160_vnetnameid --allow-vnet-access
az network vnet peering create -g $rgnameaz -n vnetpeer161 --vnet-name $az_vnetname"150" --remote-vnet $spoke161_vnetnameid --allow-vnet-access
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"160" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"161" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic

## Azure Bastion 

az network public-ip create --resource-group $rgnameaz --name bastion-ip --sku Standard --location $location

az network bastion create --name opbastion --public-ip-address bastion-ip --resource-group $rgnameaz --vnet-name $az_vnetname"150" --location $location --sku Basic


## VPN gateway
az network public-ip create --resource-group $rgnameaz --name $resourcename"pip1" --location $location --allocation-method static --sku standard
az network public-ip create --resource-group $rgnameaz --name $resourcename"pip2" --location $location --allocation-method static --sku standard

az network vnet-gateway create --name $resourcename"gw1" --public-ip-addresses $resourcename"pip1" \
--resource-group $rgnameaz --vnet $az_vnetname"140" --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1 --no-wait y

az network vnet-gateway create --name $resourcename"gw2" --public-ip-addresses $resourcename"pip2" \
--resource-group $rgnameaz --vnet $az_vnetname"150" --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1 --no-wait y


## local VPN gateway (representa o gateway VPN remoto)

## Rede 140 para 150

export remoteip150=$(az network public-ip show --resource-group $rgnameaz --name $resourcename"pip2" -o tsv --query ipAddress)
export remotevnet150=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"150" -o tsv --query addressSpace.addressPrefixes[*])


az network local-gateway create --gateway-ip-address $remoteip150 --name $resourcename"lgw1" \
--resource-group $rgnameaz --local-address-prefixes $remotevnet150 --location $location

## Rede 150 para 140

export remoteip140=$(az network public-ip show --resource-group $rgnameaz --name $resourcename"pip1" -o tsv --query ipAddress)
export remotevnet140=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"140" -o tsv --query addressSpace.addressPrefixes[*])

az network local-gateway create --gateway-ip-address $remoteip140 --name $resourcename"lgw2" \
--resource-group $rgnameaz --local-address-prefixes $remotevnet140 --location $location

## VPN connection

## Check the status of the VPN gateway

# Initialize variables
var1=$(az network vnet-gateway show --name $resourcename"gw1" --resource-group $rgnameaz -o tsv --query provisioningState)
var2=$(az network vnet-gateway show --name $resourcename"gw2" --resource-group $rgnameaz -o tsv --query provisioningState)

# Loop until one of the variables is "success"
while [[ "$var1" != "Succeeded" && "$var2" != "Succeeded" ]]; do
  
  echo "Waiting for the VPN gateway to be provisioned... $var1 / $var2"
  
  # Sleep for a while before checking again
  sleep 300

  # Check the status of the variables (this is just an example, replace with your actual checks)
  var1=$(az network vnet-gateway show --name $resourcename"gw1" --resource-group $rgnameaz -o tsv --query provisioningState)
  var2=$(az network vnet-gateway show --name $resourcename"gw2" --resource-group $rgnameaz -o tsv --query provisioningState)
done

az network vpn-connection create --name $resourcename"vpn1" --resource-group $rgnameaz --vnet-gateway1 $resourcename"gw1" \
--local-gateway2 $resourcename"lgw1" --shared-key "AzureVPNSharedKey" --location $location

az network vpn-connection create --name $resourcename"vpn2" --resource-group $rgnameaz --vnet-gateway1 $resourcename"gw2" \
--local-gateway2 $resourcename"lgw2" --shared-key "AzureVPNSharedKey" --location $location

## VPN connection status

# Initialize variables
conn1=$(az network vpn-connection show --name $resourcename"vpn1" --resource-group $rgnameaz -o tsv --query connectionStatus)
conn2=$(az network vpn-connection show --name $resourcename"vpn2" --resource-group $rgnameaz -o tsv --query connectionStatus)

# Loop until one of the variables is "success"
while [[ "$conn1" != "Connected" && "$conn2" != "Connected" ]]; do
  
  echo "VPN Connection status Conn1=$var1  Conn2=$var2"
  
  # Sleep for a while before checking again
  sleep 300

  # Check the status of the variables (this is just an example, replace with your actual checks)
  conn1=$(az network vpn-connection show --name $resourcename"vpn1" --resource-group $rgnameaz -o tsv --query connectionStatus)
  conn2=$(az network vpn-connection show --name $resourcename"vpn2" --resource-group $rgnameaz -o tsv --query connectionStatus)
done

## VM deployment

az network nic create --name "nic-router" --resource-group $rgnameaz --location $location --subnet fw_trust --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.164 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-router" --image Ubuntu2204 --vnet-name $az_vnetname"150" --subnet fw_untrust \
--size $vmsize --admin-username azureuser --generate-ssh-keys --nsg "" --nsg-rule None --public-ip-address ""

az vm deallocate  --resource-group $rgnameaz --name "vm-router"
sleep 5
az vm nic add --nic "nic-router" --vm-name "vm-router" --resource-group $rgnameaz
export nicid=$(az vm show --resource-group $rgnameaz --name "vm-router" --query "networkProfile.networkInterfaces[0].id" -o tsv)
az network nic update --ids $nicid --ip-forwarding true
sleep 5
az vm start  --resource-group $rgnameaz --name "vm-router"

az vm create --resource-group $rgnameaz --name "vm-azhost140" --image Ubuntu2204 --vnet-name $az_vnetname"140" --subnet azhosts \
--size $vmsize --admin-username azureuser --generate-ssh-keys  --nsg "" --nsg-rule None --public-ip-address "" --no-wait

az vm create --resource-group $rgnameaz --name "vm-azhost150" --image Ubuntu2204 --vnet-name $az_vnetname"150" --subnet azhosts \
--size $vmsize --admin-username azureuser --generate-ssh-keys  --nsg "" --nsg-rule None --public-ip-address "" --no-wait

az vm create --resource-group $rgnameaz --name "vm-azhost150be" --image Ubuntu2204 --vnet-name $az_vnetname"150" --subnet backend \
--size $vmsize --admin-username azureuser --generate-ssh-keys  --nsg "" --nsg-rule None --public-ip-address "" --no-wait

az vm create --resource-group $rgnameaz --name "vm-azhost160" --image Ubuntu2204 --vnet-name $az_vnetname"160" --subnet azhosts \
--size $vmsize --admin-username azureuser --generate-ssh-keys  --nsg "" --nsg-rule None --public-ip-address "" --no-wait

az vm create --resource-group $rgnameaz --name "vm-azhost161" --image Ubuntu2204 --vnet-name $az_vnetname"161" --subnet azhosts \
--size $vmsize --admin-username azureuser --generate-ssh-keys  --nsg "" --nsg-rule None --public-ip-address "" --no-wait

## Route Tables

az network route-table create --name rt-spoke160 --resource-group $rgnameaz --location $location
az network route-table route create --name "rt-vnet161" --resource-group $rgnameaz --route-table-name "rt-spoke160" --address-prefix 10.161.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.164

az network route-table create --name rt-spoke161 --resource-group $rgnameaz --location $location
az network route-table route create --name "rt-vnet160" --resource-group $rgnameaz --route-table-name "rt-spoke161" --address-prefix 10.160.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.164

az network route-table create --name rt-hubgateway --resource-group $rgnameaz --location $location
az network route-table route create --name "rt-gate2fw160" --resource-group $rgnameaz --route-table-name "rt-hubgateway" --address-prefix 10.160.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.132
az network route-table route create --name "rt-gate2fw161" --resource-group $rgnameaz --route-table-name "rt-hubgateway" --address-prefix 10.161.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.132

# Router VM linux - Enable IP Forwarding

## Enable IPv4 and IPv6 forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sed -i "/net.ipv4.ip_forward=1/ s/# *//" /etc/sysctl.conf
sed -i "/net.ipv6.conf.all.forwarding=1/ s/# *//" /etc/sysctl.conf

## Add Route Eth1
sudo ip route add 10.160.0.0/20 via 10.150.0.161
sudo ip route add 10.161.0.0/20 via 10.150.0.161

## Monitoria Routing and Tshooting Tools
sudo apt update
sudo apt install traceroute
sudo apt install net-tools

tcpdump -i etho icmp
tcpdump -i eth1 icmp


## Additional commands to fix the LAB (not all included)

## Apply Route Table to Subnets
az network vnet subnet update --resource-group $rgnameaz --vnet-name $az_vnetname"160" --name azhosts --route-table "rt-spoke160"
az network vnet subnet update --resource-group $rgnameaz --vnet-name $az_vnetname"161" --name azhosts --route-table "rt-spoke161"
az network vnet subnet update --resource-group $rgnameaz --vnet-name $az_vnetname"150" --name gatewaysubnet --route-table rt-hubgateway

## Create a Routing entry
az network route-table route create --name "rt-vnet140" --resource-group $rgnameaz --route-table-name "rt-spoke160" --address-prefix 10.140.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.150.0.164





