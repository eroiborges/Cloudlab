# =============================
# VARIABLES
# =============================

# VM Resource Group
export rg="rg-linux-entra-demo"
export location="centralus"
export vm_name="vm-linux-entra"
export admin_user="azureuser"
export image="Ubuntu2204"
export vmsize="Standard_D2s_v5"
export cloud_init_file="cloud-init.yaml"

# Network (pode estar em um Resource Group diferente)
export network_rg="rg-infra"
export vnetname="spoke01"
export subnetname="host"

# Entra ID / RBAC
export admin_group_name="LinuxAdmin"
export user_group_name="LinuxUser"


az group create --name $rg --location $location

# =============================
# NETWORK - obter ID da subnet
# =============================
# Usar o ID completo da subnet permite que a VM seja criada em um RG diferente da rede
subnet_id=$(az network vnet subnet show \
  --resource-group $network_rg \
  --vnet-name $vnetname \
  --name $subnetname \
  --query id \
  --output tsv)

# =============================
# CREATE VM
# =============================
az vm create --resource-group $rg \
  --name $vm_name --image $image \
  --admin-username $admin_user --custom-data $cloud_init_file \
  --size $vmsize --storage-sku StandardSSD_LRS \
  --subnet $subnet_id --nsg "" --nsg-rule None --public-ip-address "" \
  --assign-identity

az vm extension set \
  --publisher Microsoft.Azure.ActiveDirectory  --name AADSSHLoginForLinux \
  --resource-group $rg --vm-name $vm_name

vm_id=$(az vm show \
  --resource-group $rg \
  --name $vm_name \
  --query id \
  --output tsv)

admin_group_id=$(az ad group show \
  --group $admin_group_name \
  --query id \
  --output tsv)

user_group_id=$(az ad group show \
  --group $user_group_name \
  --query id \
  --output tsv)

## Virtual Machine Administrator Login: Users who have this role assigned can sign in to an Azure virtual machine with administrator privileges.
az role assignment create \
  --assignee-object-id $admin_group_id \
  --assignee-principal-type Group \
  --role "Virtual Machine Administrator Login" \
  --scope $vm_id

## Virtual Machine User Login: Users who have this role assigned can sign in to an Azure virtual machine with regular user privileges.
az role assignment create \
  --assignee-object-id $user_group_id \
  --assignee-principal-type Group \
  --role "Virtual Machine User Login" \
  --scope $vm_id


echo "az ssh vm --resource-group $rg --name $vm_name"