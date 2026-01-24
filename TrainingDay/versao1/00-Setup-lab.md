# Setup inicial do Laboratorio Azure Day

## Variaveis de ambiente

Definir as seguintes variaveis de ambiente. Caso a subscrição em uso tenha restrições de implementação em alguma região do Azure, alterar o valor da varivel location para uma região disponivel. Para obter o nome das regioes, utilizar o comando ``` az account list-locations --query '[].name' ```

```
export rgnameop="rg-oplab"
export rgnameaz="rg-azlab"
export location="centralus" 
export vmsize="Standard_D2s_v5" #"standard_b4ms" #"Standard_B2ms" #"Standard_D2ads_v5" #"Standard_D2s_v5"
export op_vnetname="lab-opvnet"
export az_vnetname="lab-azvnet"
export resourcename=a$(tr -dc a-z0-9 </dev/urandom | head -c 13; echo)
export admpasswd='b2xhbXVuZG8xMjM='
```
## Registrar Resource Provider

1. Data Migration Provider

    ```
    export datamigprovider=$(az provider show --namespace Microsoft.DataMigration -o tsv --query registrationState)

    if [ "$datamigprovider" != "Registered" ]; then
        az provider register --namespace Microsoft.DataMigration
        echo "Provider is not registered. Running the command..."
    fi
    ```

2. Microsoft Insight Provider

    ```
    export Insightsprovider=$(az provider show --namespace Microsoft.Insights -o tsv --query registrationState)

    if [ "$Insightsprovider" != "Registered" ]; then
        az provider register --namespace Microsoft.Insights
        echo "Provider is not registered. Running the command..."
    fi
    ```

3. Container Apps provider e Insights

    ```
    export acaprov=$(az provider show --namespace Microsoft.App -o tsv --query registrationState)
    export acainsight=$(az provider show --namespace Microsoft.App -o tsv --query registrationState)

    if [ "$acaprov" != "Registered" ]; then
        az provider register --namespace Microsoft.App
        echo "Provider is not registered. Running the command..."
    fi

    if [ "$acainsight" != "Registered" ]; then
        az provider register --namespace Microsoft.OperationalInsights
        echo "Provider is not registered. Running the command..."
    fi
    ```

## Criar Resource Group

1. Criar 2 Resource Groups para os deployments "onpremises" e "Cloud"

    ```
    az group create --name $rgnameop --location $location

    az group create --name $rgnameaz --location $location 
    ```

## Criar Storage Account

1. Criar o Storage Account

    ```
    az storage account create -n $resourcename -g $rgnameop -l $location --sku Standard_LRS

    az storage container create --name admsnap --account-name $resourcename --auth-mode login
    ```
## Log Analytic Workspace

5. Criar um workspace do Log Analytics para hospedagem de logs de diagnostico.

    ```
    az monitor log-analytics workspace create --name $resourcename --resource-group $rgnameaz --location $location --sku PerGB2018
    ```

## Azure Container Registry

1. Criar uma Container Registry para armazenar as imagens dockers utilizadas no laboratorio. 
2. Copiar a imagem [GetHeaders V2](https://hub.docker.com/repository/docker/eroiborges/getheader-backend/tags/v2/)

    ```
    az acr create --resource-group $rgnameaz --name $resourcename --sku Basic
    az acr login --name $resourcename
    az acr import   --name $resourcename   --source docker.io/eroiborges/getheader-backend:v2   --image getheader-backend:v2
    ```

3. Validar que a imagem foi copiada.

    ```
    az acr repository list   --name $resourcename
    ```

4. Criar Token e password para leitura da imagem durante o setup de outros componentes. (anotar em um bloco de notas)

    ```
    az acr scope-map create --name user-sm-pull --registry $resourcename --repository getheader-backend content/read metadata/read

    az acr token create --name sm-pull-token --registry $resourcename --scope-map user-sm-pull

    CREDS_JSON=$(az acr token credential generate --registry $resourcename --name sm-pull-token --password1 -o json)
  
    export ACR_TOKEN_USERNAME=$(echo "$CREDS_JSON" | jq -r '.username')
    export ACR_TOKEN_PASSWORD1=$(echo "$CREDS_JSON" | jq -r '.passwords[0].value')
    ```

5. Criar Variaveis para o ACR

    ```
    export acrurl=$(az acr show   --name $resourcename --query loginServer -o tsv)
    export acrrepository=$(az acr repository list   --name $resourcename --query [0] -o tsv)
    export acrimage=$(az acr repository show --name $resourcename --repository $acrrepository --query imageName -o tsv)
    export acrimagetag=$(az acr repository show-tags --name $resourcename --repository $acrrepository --query [0] -o tsv)

    export acrimageurn=$acrurl"\/"$acrimage":"$acrimagetag
    ```

## VM Jump Server

1. Criar uma VM Windows para uso inicial dos teste do laboratio.

    ```
    az vm create --resource-group $rgnameop --name vmjump --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest --size $vmsize --storage-sku StandardSSD_ZRS --vnet-name $op_vnetname --private-ip-address 10.150.0.10 --subnet ophosts --nsg "" --nsg-rule None --public-ip-address "" --authentication-type password --admin-username localadmin  --admin-password $admpasswd
    ```