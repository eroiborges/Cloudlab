#!/bin/bash

# Name of the extension to be removed
extension_name="DependencyAgentWindows"

# Get all resource groups
resource_groups=$(az group list --query "[].name" -o tsv)

# Loop through all resource groups
for rg in $resource_groups
do
  # Get all Arc enabled servers in the resource group
  servers=$(az connectedmachine list --resource-group $rg --query "[].name" -o tsv)

  # Loop through all servers
  for server in $servers
  do
    # Remove the extension
    echo "Extension from $server in $rg"
    az connectedmachine extension delete --resource-group $rg --machine-name $server --name $extension_name -y 
  done
done