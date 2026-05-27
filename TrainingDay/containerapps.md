# Laboratorio Azure Day - Azure Container APPs (ACA)

## Provisionamento ACA

1. Vamos criar uma instancia simples e aprender como o ACA funciona. Neste momento, nao vamos integrar com nosso ambiente, apenas provisionar um recurso.

    ``` 
    az extension add --name containerapp --upgrade --allow-preview true

    export lawid=$(az monitor log-analytics workspace show --name $resourcename --resource-group $rgnameaz --query customerId -o tsv)

    export lawkey=$(az monitor log-analytics workspace get-shared-keys --name $resourcename --resource-group $rgnameaz -o tsv --query primarySharedKey)

    az containerapp up \
      --name $resourcename"-apps01" \
      --resource-group $rgnameaz \
      --location $location \
      --environment 'container-apps01' \
      --image mcr.microsoft.com/k8se/quickstart:latest \
      --target-port 80 \
      --ingress external \
      --logs-workspace-id $lawid \
      --query properties.configuration.ingress.fqdn
    ```
    
2. podemos testar o scaling com um looping de requests. Ajuste a URL do comando CURL para o seu ambiente.

    ```
    for ((i=1;i<=100;i++)); do   curl -v -L --header "Connection: keep-alive" "URL"; done
    ```

## Provisionamento ACA Corporativo - Para chamar de meu \;\)

1. Criar uma Subnet para o ACA

    ```
    az network vnet subnet create --name acasubnet --resource-group $rgnameaz --vnet-name $az_vnetname --address-prefix 10.160.4.0/24 

    az network vnet subnet update --name acasubnet --resource-group $rgnameaz --vnet-name $az_vnetname --delegations Microsoft.App/environments

    export acasubnetid=$(az network vnet subnet list --resource-group $rgnameaz --vnet-name $az_vnetname -o tsv --query "[?name=='acasubnet'].id")
    ```

2. Vamos provisionar um **Environment** dedicado 

    ```
    az containerapp env create --name $resourcename"-env2" --resource-group $rgnameaz \
    --location "$location" --infrastructure-subnet-resource-id $acasubnetid \
    --logs-workspace-id $lawid --logs-workspace-key $lawkey --logs-destination log-analytics --enable-workload-profiles true --internal-only true

    export ENVIRONMENT_DEFAULT_DOMAIN=$(az containerapp env show --name $resourcename"-env" --resource-group $rgnameaz --query properties.defaultDomain --out tsv)

    export ENVIRONMENT_STATIC_IP=$(az containerapp env show --name $resourcename"-env" --resource-group $rgnameaz --query properties.staticIp --out tsv)

    export VNET_ID=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname -o tsv --query id)
    ```

3. Criar Zona Privada

    ```
    az network private-dns zone create \
      --resource-group $rgnameaz \
      --name $ENVIRONMENT_DEFAULT_DOMAIN

    az network private-dns link vnet create \
      --resource-group $rgnameaz \
      --name az_vnetname \
      --virtual-network $VNET_ID \
      --zone-name $ENVIRONMENT_DEFAULT_DOMAIN -e true

    az network private-dns record-set a add-record \
      --resource-group $rgnameaz \
      --record-set-name "*" \
      --ipv4-address $ENVIRONMENT_STATIC_IP \
      --zone-name $ENVIRONMENT_DEFAULT_DOMAIN
    ```

+ Criar um Forward condicional no DNS do servidor Windows para a zona da variavel $ENVIRONMENT_DEFAULT_DOMAIN e enviar para o IP de Inbound do Private Resolver.

> Como eu testo um registro **\"*"** com o NSLOKKUP?

4. Criar Workload Profile

    ```
    az containerapp env workload-profile add --name $resourcename"-env" --resource-group $rgnameaz --workload-profile-name dedicado --max-nodes 2 --min-nodes 1 --workload-profile-type D4
    ```

5. Criar dos apps, um com o ingress interno e o outro externo. Qual a diferença?

    ```
    az containerapp create \
      --resource-group $rgnameaz \
      --name $resourcename"-apps02" \
      --target-port 80 \
      --ingress internal \
      --image mcr.microsoft.com/k8se/quickstart:latest \
      --environment $resourcename"-env" \
      --workload-profile-name "dedicado" \
      --query properties.configuration.ingress.fqdn


    az containerapp create \
      --resource-group $rgnameaz \
      --name $resourcename"-apps03" \
      --target-port 80 \
      --ingress external \
      --image mcr.microsoft.com/k8se/quickstart:latest \
      --environment $resourcename"-env" \
      --workload-profile-name "dedicado" \
      --query properties.configuration.ingress.fqdn
    ```

## Referencias do módulo

1. [Workload profiles](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)

2. [virtual network to an Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom?tabs=bash&pivots=azure-cli)

3. [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)