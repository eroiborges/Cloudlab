#!/bin/bash

# Name of the extension to be removed
extension_name="WindowsAgent.SqlServer"
Publisher="Microsoft.AzureData" 
Target_Version="1.1.3348.364" #Source: https://github.com/MicrosoftDocs/sql-docs/blob/live/docs/sql-server/azure-arc/release-notes.md 
resource_group="rg-arcservers" # Update with your resource group name
serverlist='["server01","server02"]' #Update with your server names
tags="env=prod;dept=sql" # Update with your desired tags

for server in $(echo $serverlist | jq -r '.[]'); do   
  check=$(az connectedmachine show --machine-name $server --resource-group $resource_group -o tsv --query id 2>/dev/null)
  if [ -n "$check" ]; then
    echo "Server $server exists in resource group $resource_group. Proceeding to add extension."
    az connectedmachine extension create --resource-group $resource_group --machine-name $server --name $extension_name --publisher $Publisher --type $extension_name --type-handler-version $Target_Version --tags $tags --no-wait true
  else
    echo "Server $server does not exist in resource group $resource_group. Skipping."
    continue
  fi
done