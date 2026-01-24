# Laboratorio Azure Day - DNS

# Azure DNS

## Configurar Azure Private Zone

1. Criar zona privada para o Private Link do Storage Account e conectar a VNET Azure

    ```
    az network private-dns zone create --resource-group $rgnameaz --name "privatelink.blob.core.windows.net"

    az network private-dns link vnet create --resource-group $rgnameaz --zone-name "privatelink.blob.core.windows.net" --name dns-link --virtual-network $az_vnetname --registration-enabled false

    export peip=$(az network private-endpoint show -n private-endpoint --resource-group $rgnameop -o tsv --query customDnsConfigs[0].ipAddresses)

    az network private-dns record-set a add-record -g $rgnameaz -z "privatelink.blob.core.windows.net" -n $resourcename -a $peip
    ```

## Criar Private Resolver

1. Criar uma instancia do [Private Resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-get-started-portal#create-a-dns-resolver-inside-the-virtual-network) conectado a VNET Azure.

2. Atachar a vNIC do private resolver de inbound na subnet snet-inbound (static: 10.160.0.132) e a vNIC de outbound na subnet snet-outbound.

3. Configurar o Forward do DNS server do Servidor Windows para o IP de Inbound do Private Resolver.

4. Criar uma Forward Rule Set chamada "fsiday" com a vNIC de outbound. Add Rules

    Parametros:

      + Rule Name: fsidayzone
      + Domain Name: fsiday.local.
      + Destination IP Address: 10.150.0.4 (IP do servidor Windows)

5. Testar a resolução dos nomes de zonas privadas conectadas a NET Azure (PGSQL \ Storage Account)

6. Simular a consulta do Azure a uma zona privada fsiday.local. Utilizar o comando NSLOOKUP e o DNS server o IP do inbound do private resolver.

## Criar o Forward Condicional da Zona do PostgreSQL.

1. No servidor Windows criar um forward condicional para a zona do postgresql (postgres.database.azure.com) para o IP de Inbound do Private Resolver.

## Referencias do módulo

[What is Azure Private DNS?](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
[What is Azure DNS Private Resolver?](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
[Azure Private Endpoint DNS integration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration)