#!/bin/bash

rg="rg-arcservers"
location="centralus"
machinename="SQLFCI01"

# Windows
az connectedmachine extension create \
  --name AzureMonitorWindowsAgent \
  --publisher Microsoft.Azure.Monitor \
  --type AzureMonitorWindowsAgent \
  --machine-name $machinename \
  --resource-group $rg \
  --location $location

# Linux
az connectedmachine extension create \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --type AzureMonitorLinuxAgent \
  --machine-name $machinename \
  --resource-group $rg \
  --location $location

az monitor data-collection rule create \
  --name dcr-azmon-opentelemetric \
  --resource-group $rg \
  --location $location \
  --rule-file opentelemetric-dcr.json

ruleid=$(az monitor data-collection rule show --resource-group $rg --name dcr-azmon-opentelemetric --query id -o tsv)
arcvmid=$(az connectedmachine show --name $machinename --resource-group $rg --query id -o tsv)

az monitor data-collection rule association create \
  --name "dcr-association" \
  --rule-id $ruleid \
  --resource $arcvmid


az monitor data-collection rule show \
  --name DCRDEmo \
  --resource-group $rg

  