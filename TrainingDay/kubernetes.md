# Laboratorio Azure Day - Azure Kubernetes Service

## Provisionamento AKS

1. Adicionar uma subnet para o ambiente AKS

    ```
    az network vnet subnet create --address-prefixes 10.160.3.0/24 --name worker-aks --resource-group $rgnameaz --vnet-name $az_vnetname

    export workerakssb=$(az network vnet subnet list --resource-group $rgnameaz --vnet-name $az_vnetname -o tsv --query "[?name=='worker-aks'].id")
    export networkid=$(az network vnet show --resource-group $rgnameaz --name $az_vnetname --query "id" -o tsv)
    ```

2. Deploy da instancia AKS. Observar os parametros de Upgrade channel...o que isto significa? 

    **Validar a versão do AKS mais atual ou desejada para criar o cluster:** ```az aks get-versions -l $location```

    ```
    az aks create --resource-group $rgnameaz --name $resourcename --kubernetes-version 1.33.5 --generate-ssh-keys --load-balancer-sku standard --attach-acr $resourcename \
    --node-count 2 --network-plugin azure --network-policy calico --node-osdisk-type Managed --node-osdisk-size 30 --node-vm-size $vmsize  \
    --os-sku Ubuntu --vnet-subnet-id  $workerakssb --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 --dns-service-ip 10.2.0.10 --service-cidr 10.2.0.0/24 \
    --enable-managed-identity --enable-oidc-issuer --enable-workload-identity --auto-upgrade-channel node-image --node-os-upgrade-channel NodeImage
    ```
    
    **O cluster propositalmente não esta privado para facilitar o laboratório, mas em uma implementação produtiva, utilizar o parametro --enable-private-cluster é **extremamente** recomendado.**

3. Configurações de permissao e baixar o kubeconfig.

    ```
    aksidentity=$(az aks show --resource-group $rgnameaz --name $resourcename -o tsv --query "identity.principalId")
    sleep 5
    az role assignment create --role 4d97b98b-1d4f-4787-a291-c67834d212e7 --assignee-object-id $aksidentity --assignee-principal-type ServicePrincipal --scope $networkid

    az aks get-credentials --resource-group $rgnameaz --name $resourcename --admin
    ```

> Por que o parametro --admin no get-credential?

> Se você nao tiver o cliente kubectl instalado em sua maquina, utilize o Azure cloud shell.

## Security Updates

1. Consultar as configurações de update do cluster AKS

    ```
    az aks show -n $resourcename -g $rgnameaz -o json --query "{name:name,k8sv:currentKubernetesVersion,upgradeSettings:upgradeSettings,poolname:agentPoolProfiles[].name,nodeImage:agentPoolProfiles[].nodeImageVersion,autoUpgradeProfile:autoUpgradeProfile}"
    ```

2. Criar uma janela de manutençao para o update do cluster.

    ```
    az aks maintenanceconfiguration add -g $rgnameaz --cluster-name $resourcename --name aksManagedNodeOSUpgradeSchedule --schedule-type Weekly --day-of-week Saturday --interval-weeks 1 --duration 8 --utc-offset=-03:00 --start-time 00:00
    ```

2. Consultar Janela de manutenção existente

    ```
    az aks maintenanceconfiguration list --cluster-name $resourcename -g $rgnameaz -o json
    ```

   Consultar a lista de updates/releases do AKS em:  [AKS release tracker](https://learn.microsoft.com/en-us/azure/aks/release-tracker)

## Azure Key Vault provider for Secrets in an Azure Kubernetes Service

1. habilitar o Addon de integração com o KeyVault e apos concluido, validar se os PODs de integração foram implementados com sucesso.

    ```
    az aks enable-addons --addons azure-keyvault-secrets-provider -n $resourcename -g $rgnameaz
    ```
    ```
    kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver,secrets-store-provider-azure)'
    ```
2. Criar um Key Vault, uma secret e permissionamento RBAC. 

    ```
    az keyvault create --name $resourcename --resource-group $rgnameaz --location $location --enable-rbac-authorization

    export username=$(az account show -o tsv --query user.name)
    export tenantid=$(az account show -o tsv --query tenantId)
    export keyvaultid=$(az keyvault show --name $resourcename --resource-group $rgnameaz -o tsv --query id)

    ## Se este comando falhar, faça o IAM direto pelo portal do Azure para a sua conta de usuario.
    az role assignment create --role "Key Vault Administrator" --assignee $username --scope $keyvaultid

    az keyvault secret set --vault-name $resourcename --name ExampleSecret --value Eus0uUmS3gred0

    export aksmsiid=$(az aks show --resource-group $rgnameaz --name $resourcename --query addonProfiles.azureKeyvaultSecretsProvider.identity.objectId -o tsv)
    export aksmsicid=$(az aks show --resource-group $rgnameaz --name $resourcename --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)

    az role assignment create --role "Key Vault Certificate User"  --assignee-object-id $aksmsiid --assignee-principal-type ServicePrincipal --scope $keyvaultid
    az role assignment create --role "Key Vault Secrets User"  --assignee-object-id $aksmsiid  --assignee-principal-type ServicePrincipal --scope $keyvaultid
    ```

3. Na pasta files copia o arquivo storprovider.yaml e editar as linhas 11, 12 e 26 com os valores abaixo.

    ```
    echo "Linha 11 userAssignedIdentityID: "$aksmsicid
    echo "Linha 12 keyvaultName: " $resourcename
    echo "Linha 36 tenantId: "$tenantid
    ```

4. Salvar o arquivo alterado a aplicar no cluster AKS.

    ```
    kubectl apply -f storprovider.yaml
    ```
5. Copiar os demais arquivos .yaml de deployment e aplicar no cluster 1 a 1 para acompanhar a conexao com o Key Vault e a montagem do secret como um volume e/ou variavel de ambiente.

    + Montar o secret como um volume.

      ```
      kubectl apply -f deploy.yaml 

      kubectl get pod 
      ## copia o nome do POD do comando acima no parametro embaixo.
      kubectl exec \<nomepod> -- cat /mnt/secrets-store/ExampleSecret
      ```
    + Montar o secret como volume e Variavel de ambiente.

      ```
      kubectl apply -f deploy2.yaml 
      kubectl get pod
      kubectl exec \<nomepod> -- printenv
      ```

    + Observar que o K8S criou o objeto de secret dinamicamente.

      ```
      kubectl get secret
      ```

    + Deletar os deployment e observar que o secret será removido, quando não estiver em uso.

      ```    
      kubectl delete -f deploy.yaml
      kubectl delete -f deploy2.yaml
      kubectl get pod
      kubectl get secret
      ```
## AKS Workload Identity

1. Obter a URL do OIDC issuer

    ```
    export AKS_OIDC_ISSUER="$(az aks show --name "$resourcename" \
        --resource-group "$rgnameaz" \
        --query "oidcIssuerProfile.issuerUrl" \
        --output tsv)"
    ```

2. Criar uma User Managed Identity

    ```
    export subscriptionid=$(az account show -o tsv --query id)

    az identity create \
        --name "sp-"$resourcename \
        --resource-group "$rgnameaz" \
        --location "$location" \
        --subscription "$subscriptionid"

    export USER_ASSIGNED_CLIENT_ID="$(az identity show \
        --resource-group "$rgnameaz" \
        --name "sp-"$resourcename \
        --query 'clientId' \
        --output tsv)"
    ```
3. Criar uma conta de serviço no cluster kubernetes no namespace **"default"**

    ```
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      annotations:
        azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
      name: workload-identity-sa
      namespace: "default"
    EOF
    ```
4. Federar a credencial do Entra ID com o IODC Issuer do Cluster

    ```
    az identity federated-credential create \
        --name "myFedIdentity" \
        --identity-name ""sp-"$resourcename" \
        --resource-group "$rgnameaz" \
        --issuer "${AKS_OIDC_ISSUER}" \
        --subject system:serviceaccount:default:workload-identity-sa \
        --audience api://AzureADTokenExchange
    ```

5. Permissao RBAC no KeyVault para a User Managed Identity

    ```
    export IDENTITY_PRINCIPAL_ID="$(az identity show \
            --resource-group "$rgnameaz" \
            --name "sp-"$resourcename \
            --query 'principalId' \
            --output tsv)"

    az role assignment create \
        --assignee-object-id "${IDENTITY_PRINCIPAL_ID}" \
        --role "Key Vault Secrets User" \
        --scope "$keyvaultid" \
        --assignee-principal-type ServicePrincipal
    ```
6. Criar um POD/Deployment com uma aplicação que consuma o KeyVault usando as bibliotecas de Managed Identity

    ```
    export KEYVAULT_URL="$(az keyvault show --name $resourcename --resource-group $rgnameaz -o tsv --query properties.vaultUri)"

    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: sample-workload-identity-key-vault
      namespace: default
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: workload-identity-sa
      containers:
        - image: ghcr.io/azure/azure-workload-identity/msal-go
          name: oidc
          env:
          - name: KEYVAULT_URL
            value: ${KEYVAULT_URL}
          - name: SECRET_NAME
            value: ExampleSecret
      nodeSelector:
        kubernetes.io/os: linux
    EOF
    ```
7. Validar que o POD conseguiu fazer a leitura do KeyVault

    ```
    kubectl describe pod sample-workload-identity-key-vault | grep "SECRET_NAME:"

    kubectl logs sample-workload-identity-key-vault
    ```

## Referencias do módulo

1. [Automatically upgrade an Azure Kubernetes Service (AKS) cluster](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster?tabs=azure-cli)

2. [Azure Key Vault provider for Secrets](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)

3. [Workload ID with Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview?tabs=dotnet)