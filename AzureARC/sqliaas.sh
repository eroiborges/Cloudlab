#!/bin/bash

# Script to manage Azure VMs with SQL IaaS Extension (SqlIaasExtension)
# Usage: ./sqliaas.sh [find-with-ext|find-without-ext] [--filter <name_pattern>]

# ─────────────────────────────────────────────
# Build Resource Graph queries
# ─────────────────────────────────────────────

build_query_with_ext() {
    local filter="$1"
    local name_filter=""
    if [ -n "$filter" ]; then
        name_filter="| where name contains \"$filter\""
    fi

    cat <<EOF
resources
| where type == "microsoft.compute/virtualmachines"
$name_filter
| extend vmId = tolower(id)
| join kind=inner (
    resources
    | where type == "microsoft.compute/virtualmachines/extensions"
    | where name == "SqlIaasExtension"
    | extend vmId = tolower(substring(id, 0, indexof(id, "/extensions")))
    | project vmId
) on vmId
| project
    VMName        = name,
    Location      = location,
    ResourceGroup = resourceGroup,
    VMId          = id
| order by ResourceGroup asc, VMName asc
EOF
}

build_query_without_ext() {
    local filter="$1"
    local name_filter=""
    if [ -n "$filter" ]; then
        name_filter="| where name contains \"$filter\""
    fi

    cat <<EOF
resources
| where type == "microsoft.compute/virtualmachines"
$name_filter
| extend vmId = tolower(id)
| join kind=leftouter (
    resources
    | where type == "microsoft.compute/virtualmachines/extensions"
    | where name == "SqlIaasExtension"
    | extend vmId = tolower(substring(id, 0, indexof(id, "/extensions")))
    | project vmId, extensionName = name
) on vmId
| where isempty(extensionName)
| project
    VMName        = name,
    Location      = location,
    ResourceGroup = resourceGroup,
    VMId          = id
| order by ResourceGroup asc, VMName asc
EOF
}

# ─────────────────────────────────────────────
# Helper: validate license type
# ─────────────────────────────────────────────

validate_license_type() {
    local license_type="$1"
    case "$license_type" in
        AHUB|PAYG|DR) ;;
        *)
            echo "Error: Invalid license type '$license_type'."
            echo "Valid values: AHUB, PAYG, DR"
            exit 1
            ;;
    esac
}

# ─────────────────────────────────────────────
# Function: find VMs that HAVE SqlIaasExtension
# ─────────────────────────────────────────────

find_with_ext() {
    local filter="$1"

    if [ -n "$filter" ]; then
        echo "Finding Azure VMs with SqlIaasExtension (name filter: '$filter')..."
    else
        echo "Finding all Azure VMs with SqlIaasExtension (no name filter)..."
    fi
    echo ""

    local query result
    query=$(build_query_with_ext "$filter")

    echo "Running query..."
    result=$(az graph query -q "$query" --output json)

    echo "$result" \
        | jq -r '
            ["VMName", "Location", "ResourceGroup", "VMId"],
            (.data[] | [.VMName, .Location, .ResourceGroup, .VMId])
            | @tsv' \
        | column -t

    echo ""
    echo "Total: $(echo "$result" | jq '.count') VM(s) found."
}

# ─────────────────────────────────────────────
# Function: find VMs that DON'T have SqlIaasExtension
# ─────────────────────────────────────────────

find_without_ext() {
    local filter="$1"

    if [ -n "$filter" ]; then
        echo "Finding Azure VMs WITHOUT SqlIaasExtension (name filter: '$filter')..."
    else
        echo "Finding all Azure VMs WITHOUT SqlIaasExtension (no name filter)..."
    fi
    echo ""

    local query result
    query=$(build_query_without_ext "$filter")

    echo "Running query..."
    result=$(az graph query -q "$query" --output json)

    echo "$result" \
        | jq -r '
            ["VMName", "Location", "ResourceGroup", "VMId"],
            (.data[] | [.VMName, .Location, .ResourceGroup, .VMId])
            | @tsv' \
        | column -t

    echo ""
    echo "Total: $(echo "$result" | jq '.count') VM(s) found."
}

# ─────────────────────────────────────────────
# Function: show SQL IaaS details for a single VM
# ─────────────────────────────────────────────

show_vm() {
    local vm_name="$1"
    local resource_group="$2"

    echo "Fetching SQL IaaS details for VM '$vm_name' (RG: $resource_group)..."
    echo ""

    local result
    result=$(az sql vm show \
        --name "$vm_name" \
        --resource-group "$resource_group" \
        --expand "*" \
        --output json 2>/dev/null)

    if [ -z "$result" ] || echo "$result" | jq -e '.error' &>/dev/null; then
        echo "Error: VM '$vm_name' not found or not registered with SqlIaasExtension in RG '$resource_group'."
        exit 1
    fi

    printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
        "VMName" "ResourceGroup" "LicenseType" "Edition" "ImageOffer" "ProvisioningState"
    printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
        "------" "-------------" "-----------" "-------" "----------" "-----------------"

    echo "$result" | jq -r '[
        .name,
        .resourceGroup,
        (.sqlServerLicenseType // "N/A"),
        (.sqlImageSku // "N/A"),
        (.sqlImageOffer // "N/A"),
        (.provisioningState // "N/A")
    ] | @tsv' | while IFS=$'\t' read -r name rg license edition offer state; do
        printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
            "$name" "$rg" "$license" "$edition" "$offer" "$state"
    done
}

# ─────────────────────────────────────────────
# Function: show SQL IaaS details in batch (VMs with extension)
# ─────────────────────────────────────────────

show_batch() {
    local filter="$1"

    if [ -n "$filter" ]; then
        echo "Fetching SQL IaaS details for VMs with SqlIaasExtension (name filter: '$filter')..."
    else
        echo "Fetching SQL IaaS details for all VMs with SqlIaasExtension..."
    fi
    echo ""

    local query rg_result
    query=$(build_query_with_ext "$filter")

    echo "Running Resource Graph query..."
    rg_result=$(az graph query -q "$query" --output json)

    local count
    count=$(echo "$rg_result" | jq '.count')

    if [ "$count" -eq 0 ]; then
        echo "No VMs found."
        return
    fi

    printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
        "VMName" "ResourceGroup" "LicenseType" "Edition" "ImageOffer" "ProvisioningState"
    printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
        "------" "-------------" "-----------" "-------" "----------" "-----------------"

    echo "$rg_result" | jq -r '.data[] | [.VMName, .ResourceGroup] | @tsv' | \
    while IFS=$'\t' read -r vm_name resource_group; do
        local detail
        detail=$(az sql vm show \
            --name "$vm_name" \
            --resource-group "$resource_group" \
            --expand "*" \
            --output json 2>/dev/null)

        if [ -z "$detail" ]; then
            printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
                "$vm_name" "$resource_group" "N/A" "N/A" "N/A" "ERROR"
        else
            echo "$detail" | jq -r '[
                .name,
                .resourceGroup,
                (.sqlServerLicenseType // "N/A"),
                (.sqlImageSku // "N/A"),
                (.sqlImageOffer // "N/A"),
                (.provisioningState // "N/A")
            ] | @tsv' | while IFS=$'\t' read -r name rg license edition offer state; do
                printf '%-20s %-15s %-12s %-20s %-14s %-15s\n' \
                    "$name" "$rg" "$license" "$edition" "$offer" "$state"
            done
        fi
    done

    echo ""
    echo "Total: $count VM(s)."
}

# ─────────────────────────────────────────────
# Function: install SqlIaasExtension on a single VM
# ─────────────────────────────────────────────

install_ext_single() {
    local vm_name="$1"
    local resource_group="$2"
    local license_type="$3"

    validate_license_type "$license_type"

    echo "Fetching location for VM '$vm_name' in resource group '$resource_group'..."
    local location
    location=$(az vm show --name "$vm_name" --resource-group "$resource_group" --query location --output tsv 2>/dev/null)

    if [ -z "$location" ]; then
        echo "Error: VM '$vm_name' not found in resource group '$resource_group'."
        exit 1
    fi

    echo "Ensuring Microsoft.SqlVirtualMachine resource provider is registered..."
    az provider register --namespace Microsoft.SqlVirtualMachine --wait --output none

    echo "Installing SqlIaasExtension on '$vm_name' (license: $license_type)..."
    az sql vm create \
        --name "$vm_name" \
        --resource-group "$resource_group" \
        --location "$location" \
        --license-type "$license_type"

    if [ $? -eq 0 ]; then
        echo "  ✓ SqlIaasExtension installed on $vm_name"
    else
        echo "  ✗ Failed to install SqlIaasExtension on $vm_name"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Function: install SqlIaasExtension in batch (VMs without extension)
# ─────────────────────────────────────────────

install_ext_batch() {
    local filter="$1"
    local license_type="$2"

    validate_license_type "$license_type"

    if [ -n "$filter" ]; then
        echo "Installing SqlIaasExtension on VMs without it (name filter: '$filter', license: $license_type)..."
    else
        echo "Installing SqlIaasExtension on all VMs without it (license: $license_type)..."
    fi
    echo ""

    echo "Ensuring Microsoft.SqlVirtualMachine resource provider is registered..."
    az provider register --namespace Microsoft.SqlVirtualMachine --wait --output none

    local query result
    query=$(build_query_without_ext "$filter")

    echo "Running query..."
    result=$(az graph query -q "$query" --output json)

    local count
    count=$(echo "$result" | jq '.count')
    echo "Found $count VM(s) to process."
    echo ""

    if [ "$count" -eq 0 ]; then
        echo "No VMs to process."
        return
    fi

    echo "$result" | jq -r '.data[] | [.VMName, .ResourceGroup, .Location] | @tsv' | \
    while IFS=$'\t' read -r vm_name resource_group location; do
        echo "Processing: $vm_name (RG: $resource_group, Location: $location)"
        az sql vm create \
            --name "$vm_name" \
            --resource-group "$resource_group" \
            --location "$location" \
            --license-type "$license_type" \
            --output none

        if [ $? -eq 0 ]; then
            echo "  ✓ SqlIaasExtension installed on $vm_name"
        else
            echo "  ✗ Failed to install SqlIaasExtension on $vm_name"
        fi
        echo ""
    done

    echo "Batch install complete."
}

# ─────────────────────────────────────────────
# Function: update license type on a single VM
# ─────────────────────────────────────────────

update_license_single() {
    local vm_name="$1"
    local resource_group="$2"
    local license_type="$3"

    validate_license_type "$license_type"

    echo "Updating license type to '$license_type' for VM '$vm_name' (RG: $resource_group)..."
    az sql vm update \
        --name "$vm_name" \
        --resource-group "$resource_group" \
        --license-type "$license_type"

    if [ $? -eq 0 ]; then
        echo "  ✓ License updated to $license_type for $vm_name"
    else
        echo "  ✗ Failed to update license for $vm_name"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Function: update license type in batch (VMs with extension)
# ─────────────────────────────────────────────

update_license_batch() {
    local filter="$1"
    local license_type="$2"

    validate_license_type "$license_type"

    if [ -n "$filter" ]; then
        echo "Updating license to '$license_type' on VMs with SqlIaasExtension (name filter: '$filter')..."
    else
        echo "Updating license to '$license_type' on all VMs with SqlIaasExtension..."
    fi
    echo ""

    local query result
    query=$(build_query_with_ext "$filter")

    echo "Running query..."
    result=$(az graph query -q "$query" --output json)

    local count
    count=$(echo "$result" | jq '.count')
    echo "Found $count VM(s) to process."
    echo ""

    if [ "$count" -eq 0 ]; then
        echo "No VMs to process."
        return
    fi

    echo "$result" | jq -r '.data[] | [.VMName, .ResourceGroup] | @tsv' | \
    while IFS=$'\t' read -r vm_name resource_group; do
        echo "Processing: $vm_name (RG: $resource_group)"
        az sql vm update \
            --name "$vm_name" \
            --resource-group "$resource_group" \
            --license-type "$license_type" \
            --output none

        if [ $? -eq 0 ]; then
            echo "  ✓ License updated to $license_type for $vm_name"
        else
            echo "  ✗ Failed to update license for $vm_name"
        fi
        echo ""
    done

    echo "Batch license update complete."
}

# ─────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  find-with-ext                                         List VMs that have SqlIaasExtension"
    echo "  find-without-ext                                      List VMs that do NOT have SqlIaasExtension"
    echo "  show-vm         <vm_name> <resource_group>            Show license/edition details for a single VM"
    echo "  show-batch                                            Show license/edition details for all matching VMs"
    echo "  install-ext     <vm_name> <resource_group> <license>  Install SqlIaasExtension on a single VM"
    echo "  install-ext-batch                   <license>         Install SqlIaasExtension on all matching VMs without it"
    echo "  update-license  <vm_name> <resource_group> <license>  Update license type on a single VM"
    echo "  update-license-batch                <license>         Update license type on all matching VMs with extension"
    echo ""
    echo "Options (for find/batch commands):"
    echo "  --filter <pattern>   Filter VMs by name containing <pattern> (optional)"
    echo ""
    echo "License types:"
    echo "  AHUB   Azure Hybrid Benefit (bring your own license)"
    echo "  PAYG   Pay-As-You-Go"
    echo "  DR     Free disaster recovery replica"
    echo ""
    echo "Examples:"
    echo "  $0 find-with-ext"
    echo "  $0 find-with-ext --filter db"
    echo "  $0 find-without-ext --filter sql"
    echo "  $0 show-vm        SQLDB01 RG-INFRA"
    echo "  $0 show-batch"
    echo "  $0 show-batch     --filter db"
    echo "  $0 install-ext       SQLDB01 RG-INFRA PAYG"
    echo "  $0 install-ext-batch PAYG --filter db"
    echo "  $0 update-license    SQLDB01 RG-INFRA AHUB"
    echo "  $0 update-license-batch AHUB --filter db"
}

# ─────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────

COMMAND="$1"
shift

# Single-VM commands consume positional args before flags
case "$COMMAND" in
    "show-vm")
        VM_NAME="$1"; RESOURCE_GROUP="$2"
        shift 2 2>/dev/null || true
        ;;
    "install-ext")
        VM_NAME="$1"; RESOURCE_GROUP="$2"; LICENSE_TYPE="$3"
        shift 3 2>/dev/null || true
        ;;
    "update-license")
        VM_NAME="$1"; RESOURCE_GROUP="$2"; LICENSE_TYPE="$3"
        shift 3 2>/dev/null || true
        ;;
    "install-ext-batch"|"update-license-batch")
        LICENSE_TYPE="$1"
        shift 1 2>/dev/null || true
        ;;
esac

NAME_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)
            if [ -z "$2" ]; then
                echo "Error: --filter requires a value."
                echo ""
                show_usage
                exit 1
            fi
            NAME_FILTER="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo ""
            show_usage
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

case "$COMMAND" in
    "find-with-ext")
        find_with_ext "$NAME_FILTER"
        ;;
    "find-without-ext")
        find_without_ext "$NAME_FILTER"
        ;;
    "show-vm")
        if [ -z "$VM_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
            echo "Error: show-vm requires <vm_name> <resource_group>."
            echo ""
            show_usage
            exit 1
        fi
        show_vm "$VM_NAME" "$RESOURCE_GROUP"
        ;;
    "show-batch")
        show_batch "$NAME_FILTER"
        ;;
    "install-ext")
        if [ -z "$VM_NAME" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$LICENSE_TYPE" ]; then
            echo "Error: install-ext requires <vm_name> <resource_group> <license_type>."
            echo ""
            show_usage
            exit 1
        fi
        install_ext_single "$VM_NAME" "$RESOURCE_GROUP" "$LICENSE_TYPE"
        ;;
    "install-ext-batch")
        if [ -z "$LICENSE_TYPE" ]; then
            echo "Error: install-ext-batch requires <license_type>."
            echo ""
            show_usage
            exit 1
        fi
        install_ext_batch "$NAME_FILTER" "$LICENSE_TYPE"
        ;;
    "update-license")
        if [ -z "$VM_NAME" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$LICENSE_TYPE" ]; then
            echo "Error: update-license requires <vm_name> <resource_group> <license_type>."
            echo ""
            show_usage
            exit 1
        fi
        update_license_single "$VM_NAME" "$RESOURCE_GROUP" "$LICENSE_TYPE"
        ;;
    "update-license-batch")
        if [ -z "$LICENSE_TYPE" ]; then
            echo "Error: update-license-batch requires <license_type>."
            echo ""
            show_usage
            exit 1
        fi
        update_license_batch "$NAME_FILTER" "$LICENSE_TYPE"
        ;;
    *)
        if [ -z "$COMMAND" ]; then
            echo "Error: No command specified."
        else
            echo "Error: Unknown command '$COMMAND'"
        fi
        echo ""
        show_usage
        exit 1
        ;;
esac
