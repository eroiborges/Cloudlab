# Laboratorio Azure Day - Application Gateway / Web Application Firewall

## Criar API Backend

1. Criar uma instancia Azure Container instancia e carregar uma imagem padrao para os testes.
 
    ```
    export instancename="app01"
   
    az container create --resource-group $rgnameaz --name $instancename --location $location \
    --image $acrimageurn \
    --dns-name-label "${resourcename}01" --ports 8080 --os-type Linux \
    --memory 1 --cpu 1 \
    --assign-identity \
    --registry-username $ACR_TOKEN_USERNAME \
    --registry-password $ACR_TOKEN_PASSWORD1
    ```

2. Validar a URL e porta do Container Instance.

    ```
    az container show --resource-group $rgnameaz --name $instancename -o table --query "{URL:ipAddress.fqdn, Porta:ipAddress.ports[0].port}"
    ```
    > **Para testar o ACI utilizar:** curl -s URL:PORT/headers | jq

## Application Gateway

1. Criar uma instancia do Azure Application Gateway.
2. Adicionar nossa aplicação como backend do App Gateway.

    ```
    export httpbackend=$(az container show --resource-group $rgnameaz --name $instancename -o tsv --query "ipAddress.fqdn")
    export httpport=$(az container show --resource-group $rgnameaz --name $instancename -o tsv --query "ipAddress.ports[0].port")

    az network public-ip create --resource-group $rgnameaz --name AGPublicIPAddress --allocation-method Static --location $location --sku Standard

    az network application-gateway create --name $resourcename --location $location --resource-group $rgnameaz \
    --capacity 1 --sku Standard_v2 \
    --public-ip-address AGPublicIPAddress --vnet-name $az_vnetname --subnet apgsubnet \
    --servers $httpbackend --http-settings-port $httpport --http-settings-protocol Http \
    --priority 100

    az network application-gateway probe create --gateway-name $resourcename --name http_probe --resource-group $rgnameaz \
    --from-http-settings false --host $httpbackend --path /getip --port 8080 --protocol Http --threshold 3 --timeout 30

    az network application-gateway http-settings update --gateway-name $resourcename --name appGatewayBackendHttpSettings --resource-group $rgnameaz \
    --enable-probe true --probe http_probe --host-name-from-backend-pool true --protocol http
    ```

3. Avaliar o setup do App gateway e do backend (se estão corretos).
 
    ```
    export AppgatewayFrontEnd=$(az network public-ip show --resource-group $rgnameaz --name AGPublicIPAddress -o tsv --query ipAddress)

    #Escolhar uma das URLs.

    curl -s -X POST -d '{"id":1}' http://$AppgatewayFrontEnd/all -H 'Content-Type: application/json' | jq
    curl -s http://$AppgatewayFrontEnd/getip | jq
    curl -s http://$AppgatewayFrontEnd/headers | jq
    ```

**Output de exemplo do primeiro CURL**

![alt text](./image/appgatewayresult.jpg)

## Azure Application Gateway - Web Application Firewall.

1. 

2. Criar WAF policy

    ```
    az network application-gateway waf-policy create --name appgtw_pol --resource-group $rgnameaz --location $location --type OWASP --version 3.2 --policy-settings mode=Prevention state=Enabled
    ```

3. Atualizar o App gateway para o SKU WAF_2

    ```
    export wafpolid=$(az network application-gateway waf-policy show --resource-group $rgnameaz --name appgtw_pol --query id -o tsv)

    az network application-gateway update --name $resourcename --resource-group $rgnameaz --set sku.name=WAF_v2 --set sku.tier=WAF_v2 --set firewallPolicy.id=$wafpolid 
    ```

4. Habilitar os logs de Diagnostico

    ```
    export appgatewayid=$(az network application-gateway show --name $resourcename --resource-group $rgnameaz -o tsv --query id)

    export lawid=$(az monitor log-analytics workspace show --resource-group $rgnameaz --name $resourcename -o tsv --query id)

    az monitor diagnostic-settings create --name debugwaf --resource $appgatewayid --export-to-resource-specific true --workspace $lawid --logs "[{category:ApplicationGatewayFirewallLog,enabled:true}]"
    ```

5. Simular ataques XSS e SQL Injection

    ```
    curl -X GET "http://$AppgatewayFrontEnd/headers" -H "User-Agent: Mozilla/5.0" --data "username=admin' OR '1'='1" --data "password=admin"

    curl -X POST "http://$AppgatewayFrontEnd/all" -H "Content-Type: application/x-www-form-urlencoded" --data "input=<script>alert('XSS')</script>"
    ```

6. Aguardar a injestão dos logs e realizar consultas diretamente no Log Analytic Workspace.

    ```
    AGWFirewallLogs
    | where  Action =~ "Blocked"
    | project ClientIp, RequestUri, Message 
    ```

AzureDiagnostics
| where Category == “ApplicationGatewayFirewallLog” and action_s == “Blocked”
| summarize count(details_message_s) by details_message_s, bin(TimeGenerated, 5m)
| render barchart


## Referencias do módulo

[Azure Web Application Firewall on Azure Application Gateway](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview)
[Azure Web Application Firewall (WAF) policy overview](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/policy-overview)

## Dicas

Para e iniciar a instancia do **APP Gateway**([Stop](https://learn.microsoft.com/en-us/cli/azure/network/application-gateway?view=azure-cli-latest#az-network-application-gateway-stop)/[start](https://learn.microsoft.com/en-us/cli/azure/network/application-gateway?view=azure-cli-latest#az-network-application-gateway-start))