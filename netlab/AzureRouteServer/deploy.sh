## instruções iniciais

O Laboratorio foi desenvolvimento para executar através do AzureCLI com shell bash. Você pode utilizar uma instalação local em seu computador com o [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) ou através do [Azure Cloud Shell](<https://learn.microsoft.com/pt-br/azure/cloud-shell/overview>)

Versões do AZCli utilizadas:

| Ambiente | versão |
| -------- | ------ |
| **Desktop** | Azure-cli:2.62.0 |
| **CloudShell** | azure-cli: 2.65.0|
| | |

## Variaveis de ambiente

Definir as seguintes variaveis de ambiente. Caso a subscrição em uso tenha restrições de implementação em alguma região do Azure, alterar o valor da varivel location para uma região disponivel. Para obter o nome das regioes, utilizar o comando ``` az account list-locations --query '[].name' ```

```
export rgnameaz="rg-aznetlab-route-server"
export location="centralus" 
export vmsize="standard_b4ms" #"Standard_B2ms" #"Standard_D2ads_v5" #"Standard_D2s_v5"
export az_vnetname="lab-azvnet"
export resourcename=$(tr -dc a-z0-9 </dev/urandom | head -c 13; echo)
```

## Criar Resource Group

    ```
    az group create --name $rgnameaz --location $location
    ```
## Virtual Network

## 140 Onpremises
## 150 Azure Hub and 160 Spoke

for i in 140 150 160 161; do

  az network nsg create --resource-group $rgnameaz --name "nsg-azhosts"$i --location $location
  az network vnet create --resource-group $rgnameaz --name $az_vnetname$i --address-prefixes 10.$i.0.0/20 --subnet-name azhosts --subnet-prefixes 10.$i.0.0/26 --location $location --network-security-group "nsg-azhosts"$i
  
  case $i in
    140|150)
      # Extra command for 140 and 150
      az network vnet subnet create --name GatewaySubnet --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.0.64/26
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
      sleep 5
      az network vnet subnet create --name netlaba --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.2.0/25
      sleep 5
      az network vnet subnet create --name netlabb --resource-group $rgnameaz --vnet-name $az_vnetname$i --address-prefixes 10.$i.2.128/25
  esac

done

export hub_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"150" -o tsv --query id)
export spoke160_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"160" -o tsv --query id)
export spoke161_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname"161" -o tsv --query id)

az network vnet peering create -g $rgnameaz -n vnetpeer160 --vnet-name $az_vnetname"150" --remote-vnet $spoke160_vnetnameid --allow-vnet-access 
az network vnet peering create -g $rgnameaz -n vnetpeer161 --vnet-name $az_vnetname"150" --remote-vnet $spoke161_vnetnameid --allow-vnet-access 
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"160" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic
az network vnet peering create -g $rgnameaz -n vnetpeerhub --vnet-name $az_vnetname"161" --remote-vnet $hub_vnetnameid --allow-vnet-access --allow-forwarded-traffic

####
# Cuidado no Firewall o uso de rotas. O trafego precisa fluir entre ETH0 e ETH1 (trust e untrust).
# https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/linux-vm-multiple-virtual-network-interfaces-configuration?tabs=difsubnets%2Cubuntu
# 
####

# VM Jumpbox
az network nic create --name "nic-jumpbox" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"150" \
--ip-forwarding false --private-ip-address 10.150.0.20 --private-ip-address-version IPv4  

az network public-ip create --resource-group $rgnameaz --name "pip-jumpbox" --location $location --allocation-method Static --sku Standard
az network nic ip-config update --name "ipconfig1" --nic-name "nic-jumpbox" --resource-group $rgnameaz --public-ip-address "pip-jumpbox" 

az vm create --resource-group $rgnameaz --name "vm-jumpbox-01" --image Ubuntu2204 --size $vmsize --nics "nic-jumpbox" --admin-username azureuser --generate-ssh-keys --no-wait

# update NSG to allow  SSH
export myip=$(curl -s -k ifconfig.me)
az network nsg rule create --resource-group $rgnameaz --nsg-name "nsg-azhosts150" --name "Allow-SSH" --protocol Tcp --direction Inbound --priority 1001 --source-address-prefixes "$myip" --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow


# VM Firewall IP Forwarding NICs
az network nic create --name "nic-fw-untrust" --resource-group $rgnameaz --location $location --subnet fw_untrust --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.132 --private-ip-address-version IPv4 
az network nic create --name "nic-fw-trust" --resource-group $rgnameaz --location $location --subnet fw_trust --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.164 --private-ip-address-version IPv4 

# VM Firewall
az vm create --resource-group $rgnameaz --name "vm-firewall-01" --image Ubuntu2204 --size $vmsize --nics "nic-fw-untrust" "nic-fw-trust" --admin-username azureuser --generate-ssh-keys --no-wait

# VM Firewall Public IP
az network public-ip create --resource-group $rgnameaz --name "pip-firewall" --location $location --allocation-method Static --sku Standard
az network nic ip-config update --name "ipconfig1" --nic-name "nic-fw-untrust" --resource-group $rgnameaz --public-ip-address "pip-firewall"

## VM Cliente on VNET 161
az network nic create --name "nic-cliente01" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"161" \
 --private-ip-address 10.161.0.8 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-cliente01" --image Ubuntu2204 --size $vmsize --nics "nic-cliente01" --admin-username azureuser --generate-ssh-keys --no-wait

 ## VM Cliente on VNET 160
az network nic create --name "nic-cliente02" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"160" \
 --private-ip-address 10.160.0.8 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-cliente02" --image Ubuntu2204 --size $vmsize --nics "nic-cliente02" --admin-username azureuser --generate-ssh-keys --no-wait

# VM BGP
az network nic create --name "nic-bgp01" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.10 --private-ip-address-version IPv4

az network nic create --name "nic-bgp02" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.0.12 --private-ip-address-version IPv4

## secondary nic
az network nic create --name "nic-bgp01-secondary" --resource-group $rgnameaz --location $location --subnet netlaba --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.2.4 --private-ip-address-version IPv4

az network nic create --name "nic-bgp02-secondary" --resource-group $rgnameaz --location $location --subnet netlabb --vnet-name $az_vnetname"150" \
--ip-forwarding true --private-ip-address 10.150.2.132 --private-ip-address-version IPv4


az vm create --resource-group $rgnameaz --name "vm-router-bgp01" --image Ubuntu2204 --size $vmsize --nics "nic-bgp01" "nic-bgp01-secondary" --admin-username azureuser --generate-ssh-keys --no-wait

az vm create --resource-group $rgnameaz --name "vm-router-bgp02" --image Ubuntu2204 --size $vmsize --nics "nic-bgp02" "nic-bgp02-secondary" --admin-username azureuser --generate-ssh-keys --no-wait


# ## stop and deallocate VMs to attach secondary nics
# az vm deallocate --resource-group $rgnameaz --name "vm-router-bgp01"
# az vm deallocate --resource-group $rgnameaz --name "vm-router-bgp02"  
# sleep 5
# az vm nic add --resource-group $rgnameaz --vm-name "vm-router-bgp01" --nics "nic-bgp01-secondary"
# az vm nic add --resource-group $rgnameaz --vm-name "vm-router-bgp02" --nics "nic-bgp02-secondary"
# sleep 5
# # start VMs again
# az vm start --resource-group $rgnameaz --name "vm-router-bgp01"
# az vm start --resource-group $rgnameaz --name "vm-router-bgp02"

# router 3 on VNET 160
az network nic create --name "nic-bgp03" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"160" \
--ip-forwarding true --private-ip-address 10.160.0.4 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-router-bgp03" --image Ubuntu2204 --size $vmsize --nics "nic-bgp03" --admin-username azureuser --generate-ssh-keys --no-wait

# router 4 on VNET 161
az network nic create --name "nic-bgp04" --resource-group $rgnameaz --location $location --subnet azhosts --vnet-name $az_vnetname"161" \
--ip-forwarding true --private-ip-address 10.161.0.4 --private-ip-address-version IPv4

az vm create --resource-group $rgnameaz --name "vm-router-bgp04" --image Ubuntu2204 --size $vmsize --nics "nic-bgp04" --admin-username azureuser --generate-ssh-keys --no-wait



## route server
subnetId=$(az network vnet subnet show --name 'RouteServerSubnet' --resource-group $rgnameaz --vnet-name $az_vnetname"150" --query id -o tsv)

# Create a Standard public IP for Route Server
az network public-ip create --resource-group $rgnameaz --name 'RouteServerIP' --sku Standard --version 'IPv4'

# Create the Route Server
az network routeserver create --name 'demoars' --resource-group $rgnameaz --hosted-subnet $subnetId --public-ip-address 'RouteServerIP'

# Get Route Server details for NVA configuration
az network routeserver show --resource-group $rgnameaz --name 'demoars'   --query '{id:id, provisioningState:provisioningState, hostedSubnet:hostedSubnet, virtualRouterIps:virtualRouterIps, virtualRouterAsn:virtualRouterAsn}' -o json


# Create BGP peering with the network virtual appliance
az network routeserver peering create --name 'firewall' --peer-ip '10.150.0.164' --peer-asn '65002' --routeserver 'demoars' --resource-group $rgnameaz