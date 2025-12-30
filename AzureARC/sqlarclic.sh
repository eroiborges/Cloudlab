#!/bin/bash

# Script to manage Arc-enabled SQL Server license types
# Usage: ./sqlarclic.sh [list|update]

query='resources
| where type == "microsoft.hybridcompute/machines/extensions"
| where properties.type in ("WindowsAgent.SqlServer","LinuxAgent.SqlServer")
| extend machineId = substring(id, 0, indexof(id, "/extensions"))
| extend licenseType = iff(isempty(properties.settings.LicenseType) or properties.settings.LicenseType == "", "Configuration needed", properties.settings.LicenseType)
| extend extensionName = substring(id, indexof(id, "/extensions/") + 12)
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
) on $left.machineId == $right.id
| project 
    MachineId = machineId,
    MachineName = name1,
    Location = location1, 
    ResourceGroup = resourceGroup1,
    LicenseType = licenseType,
    ExtensionName = extensionName'

# Function to list SQL Server license types
list_sql_licenses() {
    echo "Listing Arc-enabled SQL Server machines and their license types..."
    echo ""
    az graph query -q "$query" --output json | jq -r '["MachineId", "MachineName", "Location", "ResourceGroup", "LicenseType", "ExtensionName"], (.data[] | [.MachineId, .MachineName, .Location, .ResourceGroup, .LicenseType, .ExtensionName]) | @tsv' | column -t
}

# Function to update SQL Server license types to specified type
update_sql_licenses() {
    local license_type="$1"
    
    # Validate license type
    case "$license_type" in
        "PAYG"|"Paid"|"LicenseOnly")
            ;;
        *)
            echo "Error: Invalid license type '$license_type'"
            echo "Valid license types are: PAYG, Paid, LicenseOnly"
            exit 1
            ;;
    esac
    
    echo "Updating SQL Server license type to $license_type..."
    echo ""
    
    # Get the machine IDs, extension names and update license type
    az graph query -q "$query" --output json | jq -r '.data[] | [.MachineId, .ExtensionName] | @tsv' | while IFS=$'\t' read -r machine_id extension_name; do
        echo "Processing machine: $machine_id"
        echo "Extension name: $extension_name"
        
        # Extract resource group and machine name from the full resource ID
        resource_group=$(echo "$machine_id" | cut -d'/' -f5)
        machine_name=$(echo "$machine_id" | cut -d'/' -f9)
        
        echo "  Resource Group: $resource_group"
        echo "  Machine Name: $machine_name"
        
        # Update the SQL Server extension license type
        az connectedmachine extension update \
            --resource-group "$resource_group" \
            --machine-name "$machine_name" \
            --name "$extension_name" \
            --settings "{\"LicenseType\":\"$license_type\"}" \
            --no-wait
        
        if [ $? -eq 0 ]; then
            echo "  ✓ License type update to $license_type initiated for $machine_name"
        else
            echo "  ✗ Failed to update license type for $machine_name"
        fi
        echo ""
    done
    
    echo "All updates to $license_type initiated. License type changes may take a few minutes to apply."
}

# Function to update a single SQL Server license type
update_single_sql_license() {
    local resource_group="$1"
    local machine_name="$2"
    local license_type="$3"
    
    # Validate license type
    case "$license_type" in
        "PAYG"|"Paid"|"LicenseOnly")
            ;;
        *)
            echo "Error: Invalid license type '$license_type'"
            echo "Valid license types are: PAYG, Paid, LicenseOnly"
            exit 1
            ;;
    esac
    
    echo "Updating SQL Server license type to $license_type for machine: $machine_name"
    echo "Resource Group: $resource_group"
    echo ""
    
    # Get the extension name for this specific machine
    single_query="resources
    | where type == \"microsoft.hybridcompute/machines/extensions\"
    | where properties.type in (\"WindowsAgent.SqlServer\",\"LinuxAgent.SqlServer\")
    | extend machineId = substring(id, 0, indexof(id, \"/extensions\"))
    | extend extensionName = substring(id, indexof(id, \"/extensions/\") + 12)
    | join kind=inner (
        resources
        | where type == \"microsoft.hybridcompute/machines\"
        | where name == \"$machine_name\"
        | where resourceGroup == \"$resource_group\"
    ) on \$left.machineId == \$right.id
    | project ExtensionName = extensionName"
    
    extension_name=$(az graph query -q "$single_query" --output json | jq -r '.data[0].ExtensionName // empty')
    
    if [ -z "$extension_name" ]; then
        echo "Error: Could not find SQL Server extension for machine '$machine_name' in resource group '$resource_group'"
        echo "Make sure the machine exists and has SQL Server extension installed."
        exit 1
    fi
    
    echo "Found extension: $extension_name"
    echo ""
    
    # Update the SQL Server extension license type
    az connectedmachine extension update \
        --resource-group "$resource_group" \
        --machine-name "$machine_name" \
        --name "$extension_name" \
        --settings "{\"LicenseType\":\"$license_type\"}" \
        --no-wait
    
    if [ $? -eq 0 ]; then
        echo "✓ License type update to $license_type initiated for $machine_name"
        echo "License type change may take a few minutes to apply."
    else
        echo "✗ Failed to update license type for $machine_name"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [list|update <license_type>|update-single <resource_group> <machine_name> <license_type>]"
    echo ""
    echo "Commands:"
    echo "  list                                           - Display Arc-enabled SQL Server machines and their license types"
    echo "  update <license_type>                          - Update all SQL Server license types to specified type"
    echo "  update-single <resource_group> <machine_name> <license_type> - Update specific machine license type"
    echo ""
    echo "Valid license types:"
    echo "  PAYG        - Pay-As-You-Go (pay for SQL Server usage)"
    echo "  Paid        - SQL with onpremises licenses and Software Assurance"
    echo "  LicenseOnly - License only (no Software Assurance)"
    echo ""
    echo "Examples:"
    echo "  $0 list                                        # Show current license status"
    echo "  $0 update PAYG                                 # Change all licenses to Pay-As-You-Go"
    echo "  $0 update Paid                                 # Change all licenses to Azure Hybrid Benefit"
    echo "  $0 update LicenseOnly                          # Change all licenses to License Only"
    echo "  $0 update-single rg-arcservers SQL19-01 PAYG  # Change specific machine to Pay-As-You-Go"
}

# Main script logic
case "$1" in
    "list")
        list_sql_licenses
        ;;
    "update")
        if [ -z "$2" ]; then
            echo "Error: License type parameter is required for update command."
            echo ""
            show_usage
            exit 1
        fi
        update_sql_licenses "$2"
        ;;
    "update-single")
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "Error: Resource group, machine name, and license type parameters are required for update-single command."
            echo ""
            show_usage
            exit 1
        fi
        update_single_sql_license "$2" "$3" "$4"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac 

