# Variables
export RESOURCE_GROUP="rg-arcservers"
export EXTENSION_NAME="WindowsAgent.SqlServer"

# Get the list of VM names
export arcvmnames=$(az connectedmachine list -g "$RESOURCE_GROUP" --query "[].name" -o tsv)

# Loop through each VM name
for vm in $arcvmnames; do
  echo "Checking VM: $vm"

  az connectedmachine extension show --name "$EXTENSION_NAME" --machine-name "$vm" --resource-group "$RESOURCE_GROUP" &> /dev/null

  if [ $? -eq 0 ]; then
    echo "Extension $EXTENSION_NAME exists on $vm"
    echo "updating extension $EXTENSION_NAME from $vm"
    az connectedmachine extension update --extension-name $EXTENSION_NAME --type WindowsAgent.SqlServer --publisher Microsoft.AzureData --type-handler-version 1.1.3049.285 --machine-name $vm -g $RESOURCE_GROUP --no-wait true
  else
    echo "Extension $EXTENSION_NAME not found on $vm, moving to next"
  fi
done


az connectedmachine extension create --extension-name "WindowsAgent.SqlServer" --type WindowsAgent.SqlServer --publisher Microsoft.AzureData --type-handler-version 1.1.3049.285 --machine-name $vm -g $RESOURCE_GROUP --no-wait true
