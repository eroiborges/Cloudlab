# Laboratorio Azure Day - Monitoring

## VNET log Flow

Durante todos os exercicios, os logs das VNETs foram capturados como auditoria do trafego e enviados ao Log Analytic Workspace, o que me permite analisar os logs das tabelas NTAIpDetails, NTANetAnalytics e NTATopologyDetails por trafegos indesejados.

1. No portal Azure abrir o network Watcher > Traffic Analytic. Observar o DashBoard os fluxos TCP/UDP, Pacotes e bytes enviados entre os workloads.  

    + Referencia sobre o [VNET log Flow](https://techcommunity.microsoft.com/blog/azurenetworkingblog/network-traffic-observability-with-virtual-network-flow-logs/4112907)

2. No portal Azure Abrir o Log Analytic Workspace para executar consultas diretamente nas tabelas.

    + Referencia sobre as [tabelas do VNET log Flow](https://techcommunity.microsoft.com/blog/fasttrackforazureblog/virtual-network-flow-logs-recipes/4134337)

    ```
    NTANetAnalytics
    | where FlowDirection contains "Outbound" and (BytesDestToSrc > 0 or BytesSrcToDest > 0)
    | extend DestIP = tostring(split(DestPublicIps, "|")[0])
    | project TimeGenerated, FlowType, SrcIp, DestIP, DestToSrc=format_bytes(BytesDestToSrc, 2),SrcToDest=format_bytes(BytesSrcToDest , 2)


    NTANetAnalytics
    | where FlowDirection contains "Inbound" and (BytesDestToSrc > 0 or BytesSrcToDest > 0)
    | extend cSrcIP = tostring(split(SrcPublicIps, "|")[0])
    | project TimeGenerated, FlowType, cSrcIP, DestIp, DestToSrc=format_bytes(BytesDestToSrc, 2) ,SrcToDest=format_bytes(BytesSrcToDest , 2)
    ```

## Referencias do módulo

1. [Virtual network flow logs](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview )
