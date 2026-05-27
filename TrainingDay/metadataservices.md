# Laboratorio Azure Day - Metadata Service


## Azure Metadata service

Abrir o powershell do Servidor Windows e executar cada query

1. instance Metadata

    ```
    Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertTo-Json -Depth 64
    ```
  
2. Scheduled Events

    ```
    Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" | ConvertTo-Json -Depth 64
    ```

## Referencias do módulo

1. [Azure Instance Metadata Service](https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service?tabs=windows)
2. [Scheduled Events for Windows VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/scheduled-events)
3. [Scheduled Events for Linux VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/scheduled-events)