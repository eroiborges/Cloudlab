# Laboratorio Azure Day - Azure Network and Security

## Setup Network Enviroment

### Onpremises Network

1. Criar a VNET que representa o ambiente Onpremises.

    ```
    az network nsg create --resource-group $rgnameop --name nsg-ophosts --location $location

    az network vnet create --resource-group $rgnameop --name $op_vnetname --address-prefixes 10.150.0.0/20 --subnet-name ophosts --subnet-prefixes 10.150.0.0/27 --location $location --network-security-group nsg-ophosts --dns-servers 10.150.0.4 168.63.129.16

    az network vnet subnet create --name AzureBastionSubnet --resource-group $rgnameop --vnet-name $op_vnetname --address-prefix 10.150.0.64/26
    ```

### Cloud Network

2. Criar Network Security Groups

    ```
    az network nsg create --resource-group $rgnameaz --name nsg-azhosts --location $location

    az network nsg create --resource-group $rgnameaz --name nsg-appgateway --location $location
 
    az network nsg rule create \
    --resource-group $rgnameaz \
    --nsg-name nsg-appgateway \
    --name Allow-GatewayManager-Inbound \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefix GatewayManager \
    --source-port-range '*' \
    --destination-address-prefix '*' \
    --destination-port-range 65200-65535


    az network nsg rule create \
    --resource-group $rgnameaz \
    --nsg-name nsg-appgateway \
    --name Allow-AzureLoadBalancer-Inbound \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefix AzureLoadBalancer \
    --source-port-range '*' \
    --destination-address-prefix '*' \
    --destination-port-range '*'


    az network nsg rule create \
    --resource-group $rgnameaz \
    --nsg-name nsg-appgateway \
    --name Allow-Client-Traffic \
    --priority 120 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefix Internet \
    --destination-address-prefix '*' \
    --destination-port-range 80 443


    az network nsg rule create \
    --resource-group $rgnameaz \
    --nsg-name nsg-appgateway \
    --name Allow-Internet-Outbound \
    --priority 100 \
    --direction Outbound \
    --access Allow \
    --protocol '*' \
    --source-address-prefix '*' \
    --destination-address-prefix Internet \
    --destination-port-range '*'
    ```

3. Criar a VNET que representa o ambiente Azure.


    ```
    az network vnet create --resource-group $rgnameaz --name $az_vnetname --address-prefixes 10.160.0.0/20 --subnet-name azhosts --subnet-prefixes 10.160.0.0/27 --location $location --network-security-group nsg-azhosts 

    az network vnet subnet create --name pgsqlnet --resource-group $rgnameaz --vnet-name $az_vnetname --address-prefix 10.160.0.64/26

    az network vnet subnet create --name snet-inbound --resource-group $rgnameaz --vnet-name $az_vnetname --address-prefix 10.160.0.128/28

    az network vnet subnet create --name snet-outbound --resource-group $rgnameaz --vnet-name $az_vnetname --address-prefix 10.160.0.144/28

    az network vnet subnet create --name apgsubnet --resource-group $rgnameaz --vnet-name $az_vnetname --address-prefix 10.160.1.0/24 --network-security-group nsg-appgateway
    ```

### VNET Peering

4. Criar um VNET peering (conexão) entre as 2 VNETs simulando a conexão de uma VPN ou Express Route.

    ```
    export op_vnetnameid=$(az network vnet show --resource-group $rgnameop --name $op_vnetname -o tsv --query id)
    export az_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname -o tsv --query id)

    az network vnet peering create -g $rgnameop -n vnetpeerop --vnet-name $op_vnetname --remote-vnet $az_vnetnameid --allow-vnet-access

    az network vnet peering create -g $rgnameaz -n vnetpeeraz --vnet-name $az_vnetname --remote-vnet $op_vnetnameid --allow-vnet-access
    ```

### Azure Bastion

5. O acesso aos servidores via RDP ou SSH serão feitos através do serviço de Bastion.

    ```
    az network public-ip create --resource-group $rgnameop --name bastion-ip --sku Standard --location $location

    az network bastion create --name opbastion --public-ip-address bastion-ip --resource-group $rgnameop --vnet-name $op_vnetname --location $location --sku Basic
    ```

### Azure Natgateway

6. Provisionar um NAT gateway para garantir conexão outbound para internet das VMs. 

    ```   
    XCLUDE_SUBNETS=(
    "AzureBastionSubnet"
    "GatewaySubnet"
    "AzureFirewallSubnet"
    "snet-inbound"
    "snet-outbound"
    )

    # Função para checar se valor está no array
    in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
    }

    # Loop externo: percorre os pares RG:VNET
    for RG_VNET in "$rgnameop:$op_vnetname" "$rgnameaz:$az_vnetname"; do
    IFS=':' read -r RG_NAME VNET_NAME <<< "$RG_VNET"
    echo "==== Processando VNet '$VNET_NAME' no RG '$RG_NAME' ===="

    # --------- [NOVO] Criar/obter Public IP para o NAT desta VNet ---------
    PIP_NAME="natgwip-${resourcename}-${VNET_NAME}"
    az network public-ip create \
        --resource-group "$RG_NAME" \
        --name "$PIP_NAME" \
        --location "$location" \
        --sku Standard \
        --allocation-method Static \
        --version IPv4 \
        --only-show-errors 1>/dev/null

    # --------- [NOVO] Criar/obter NAT Gateway desta VNet ---------
    NATGW_NAME="natgw-${resourcename}-${VNET_NAME}"
    az network nat gateway create \
        --resource-group "$RG_NAME" \
        --name "$NATGW_NAME" \
        --location "$location" \
        --public-ip-addresses "$PIP_NAME" \
        --idle-timeout 4 \
        --only-show-errors 1>/dev/null

    # --------- [NOVO] Capturar ID do NAT desta VNet ---------
    NATGW_ID=$(az network nat gateway show \
        --resource-group "$RG_NAME" \
        --name "$NATGW_NAME" \
        --query id -o tsv)

    if [[ -z "$NATGW_ID" ]]; then
        echo "[ERROR] Não foi possível obter o ID do NAT Gateway '$NATGW_NAME' no RG '$RG_NAME'. Abortando este par."
        continue
    fi

    # Lista as subnets da VNet atual
    readarray -t SUBNETS < <(az network vnet subnet list \
        --resource-group "$RG_NAME" \
        --vnet-name "$VNET_NAME" \
        -o tsv --query [].name)

    # Loop nas subnets (sua lógica original)
    for subnet in "${SUBNETS[@]}"; do
        if in_array "$subnet" "${EXCLUDE_SUBNETS[@]}"; then
            echo "[SKIP] Subnet ignorada: $subnet"
            continue
        fi

        echo "[RUN] Processando subnet: $subnet"
        az network vnet subnet update \
            --resource-group "$RG_NAME" \
            --vnet-name "$VNET_NAME" \
            --name "$subnet" \
            --nat-gateway "$NATGW_ID" \
            --only-show-errors 1>/dev/null
        echo "[OK] Subnet '$subnet' associada ao NAT '$NATGW_NAME'"
    done
    done

    echo "==== Concluído com sucesso. ===="

    ```
### VNET Log Flow

7. Ativar o envio dos logs de VNET para o Workspace.

    ```
    export storageaccountid=$(az storage account show --resource-group $rgnameop --name $resourcename -o tsv --query id)

    export lawid=$(az monitor log-analytics workspace show --resource-group $rgnameaz --name $resourcename -o tsv --query id)

    az network watcher flow-log create --location $location --name VNetFlowLog --resource-group $rgnameop --vnet $op_vnetname --storage-account $storageaccountid --workspace $lawid --interval 10 --traffic-analytics true

    az network watcher flow-log create --location $location --name VNetFlowLogaz --resource-group $rgnameaz --vnet $az_vnetname --storage-account $storageaccountid --workspace $lawid --interval 10 --traffic-analytics true

    ```
## Network Security Group e VNET Peering

1. Mostrar a estrutura da NSG na Tag Virtual Network e porque a comunicacao do entre VNETs funciona sem precisar criar uma regra explicitas.
2. Explicar as opções de VNET Peering.

## Service Endpoint / VNET Inject e Private Endpoint.

1. O que é o Service Enpoint, como ele influencia o routing e dicas. 

2. Criar um service endpoint para o serviço de SQL

    ```
    az network vnet subnet update --resource-group $rgnameop --vnet-name $op_vnetname --name ophosts --service-endpoints Microsoft.SQL

    az network vnet subnet update --resource-group $rgnameaz --vnet-name $az_vnetname --name azhosts --service-endpoints Microsoft.SQL
    ```


## Criar Private Endpoint do Storage Account

1. Criar Subnet para o Private Endpoint na VNET Azure.

    ```
    az network vnet subnet create --address-prefixes 10.160.0.32/27 --name PrivEnd --resource-group $rgnameaz --vnet-name $az_vnetname
    ```

2. Criar um private endpoint para o Storage Account na VNET Azure.

    ```
    export storageaccountid=$(az storage account show -n $resourcename -g $rgnameop -o tsv --query id)
    export az_vnetnameid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname -o tsv --query id)

    PrivEndsubnet=$(az network vnet subnet list --resource-group $rgnameaz --vnet-name $az_vnetname -o tsv --query "[?name=='PrivEnd'].id")

    az network private-endpoint create --connection-name storage-conn --name private-endpoint --private-connection-resource-id $storageaccountid --resource-group $rgnameop --subnet $PrivEndsubnet --group-id blob
    ```

3. Observar o conceito Network Policy sobre as rotas efetivas das VMs.

    ```
    export nicid=$(az vm show -n vmjump -g $rgnameop -o tsv --query networkProfile.networkInterfaces[0].id)

    az network nic show-effective-route-table --ids $nicid -o table
    ```

4. Habilitar Network Policy

    ```
    az network vnet subnet update --disable-private-endpoint-network-policies false --name PrivEnd --resource-group $rgnameaz --vnet-name $az_vnetname
    ``` 

    **Alterou algo nas rotas efetivas?**

5. Invalidar rota /32 criando uma UDR para o range da VNET 10.160.0.0/20 passar por um Firewall (rota fake)

    ```
    az network route-table create --name azfw-routetable --resource-group $rgnameop --location $location

    az network route-table route create --name private-2-firewall --resource-group $rgnameop --route-table-name azfw-routetable --address-prefix 10.160.0.0/20 --next-hop-type VirtualAppliance --next-hop-ip-address 10.0.100.4

    az network vnet subnet update --resource-group $rgnameop --vnet-name $op_vnetname --name ophosts --route-table azfw-routetable
    ```

6. Verificar a rota efetiva novamente

    ```
    az network nic show-effective-route-table --ids $nicid -o table
    ```
    **Alterou algo na rota efetiva agora?**

7. Remover a UDR para não impactar o laborario.

    ```
    az network vnet subnet update --resource-group $rgnameop --vnet-name $op_vnetname --name ophosts --route-table null
    ```

## Referencias do módulo

1. [Default outbound access in Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)
2. [Virtual Network Peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview)
3. [Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
4. [Virtual Network service endpoints](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-service-endpoints-overview)
5. [What is a private endpoint?](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
6. [Virtual network traffic routing](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview)
7. [Network Policy](https://learn.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy?tabs=network-policy-cli)
8. [Network Security Perimeter](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts)