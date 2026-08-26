#!/usr/bin/env bash
set -euo pipefail

required_variables=(
  RESOURCE_GROUP REGION FILE_SHARE_NAME PROVISIONED_STORAGE_GIB REDUNDANCY
  VNET_RESOURCE_GROUP VNET_NAME PRIVATE_ENDPOINT_SUBNET
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Missing required variable: %s\n' "$variable_name" >&2
    exit 2
  fi
done

if [[ ! "$FILE_SHARE_NAME" =~ ^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$ ]]; then
  printf 'FILE_SHARE_NAME must be 3-63 lowercase letters, numbers, or hyphens.\n' >&2
  exit 2
fi

if [[ ! "$PROVISIONED_STORAGE_GIB" =~ ^[0-9]+$ ]] ||
   (( PROVISIONED_STORAGE_GIB < 32 || PROVISIONED_STORAGE_GIB > 262144 )); then
  printf 'PROVISIONED_STORAGE_GIB must be between 32 and 262144.\n' >&2
  exit 2
fi

if [[ "$REDUNDANCY" != "Local" && "$REDUNDANCY" != "Zone" ]]; then
  printf 'REDUNDANCY must be Local or Zone.\n' >&2
  exit 2
fi

az account show --output none
az extension add --name fileshare --upgrade --output none
az provider register --namespace Microsoft.FileShares --wait
az provider register --namespace Microsoft.Storage --wait

if az fileshare show --resource-group "$RESOURCE_GROUP" --name "$FILE_SHARE_NAME" --output none 2>/dev/null; then
  printf 'A file share with this name already exists; review it instead of overwriting it.\n' >&2
  exit 3
fi

subnet_id=$(az network vnet subnet show \
  --resource-group "$VNET_RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$PRIVATE_ENDPOINT_SUBNET" \
  --query id --output tsv)

vnet_id=$(az network vnet show \
  --resource-group "$VNET_RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --query id --output tsv)

vnet_region=$(az network vnet show \
  --resource-group "$VNET_RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --query location --output tsv)

az fileshare create \
  --name "$FILE_SHARE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$REGION" \
  --provisioned-storage-gib "$PROVISIONED_STORAGE_GIB" \
  --protocol NFS \
  --redundancy "$REDUNDANCY" \
  --output none

share_id=$(az fileshare show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FILE_SHARE_NAME" \
  --query id --output tsv)

host_name=$(az fileshare show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FILE_SHARE_NAME" \
  --query properties.hostName --output tsv)

dns_record_name=${host_name%%.*}
private_endpoint_name="${dns_record_name}-private-endpoint"

if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "$private_endpoint_name" --output none 2>/dev/null; then
  printf 'The private endpoint already exists; review it instead of overwriting it.\n' >&2
  exit 3
fi

az network vnet subnet update \
  --ids "$subnet_id" \
  --disable-private-endpoint-network-policies true \
  --output none

private_endpoint_id=$(az network private-endpoint create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$private_endpoint_name" \
  --location "$vnet_region" \
  --subnet "$subnet_id" \
  --private-connection-resource-id "$share_id" \
  --group-id FileShare \
  --connection-name "${dns_record_name}-connection" \
  --query id --output tsv)

storage_suffix=$(az cloud show --query suffixes.storageEndpoint --output tsv)
dns_zone_name="privatelink.file.${storage_suffix}"
dns_zone_resource_group=''

possible_dns_zones=$(az network private-dns zone list \
  --query "[?name == '$dns_zone_name'].id" --output tsv)

for possible_dns_zone in $possible_dns_zones; do
  possible_resource_group=$(az resource show \
    --ids "$possible_dns_zone" --query resourceGroup --output tsv)
  existing_link=$(az network private-dns link vnet list \
    --resource-group "$possible_resource_group" \
    --zone-name "$dns_zone_name" \
    --query "[?virtualNetwork.id == '$vnet_id'].id" --output tsv)
  if [[ -n "$existing_link" ]]; then
    dns_zone_resource_group=$possible_resource_group
    break
  fi
done

if [[ -z "$dns_zone_resource_group" ]]; then
  dns_zone_resource_group=$VNET_RESOURCE_GROUP
  if ! az network private-dns zone show \
    --resource-group "$dns_zone_resource_group" \
    --name "$dns_zone_name" --output none 2>/dev/null; then
  az network private-dns zone create \
    --resource-group "$dns_zone_resource_group" \
    --name "$dns_zone_name" \
    --output none
  fi

  dns_link_name="${VNET_NAME}-nfs-link"
  if az network private-dns link vnet show \
    --resource-group "$dns_zone_resource_group" \
    --zone-name "$dns_zone_name" \
    --name "$dns_link_name" --output none 2>/dev/null; then
    printf 'The DNS link name already exists for another network; review it manually.\n' >&2
    exit 3
  fi
  az network private-dns link vnet create \
    --resource-group "$dns_zone_resource_group" \
    --zone-name "$dns_zone_name" \
    --name "$dns_link_name" \
    --virtual-network "$vnet_id" \
    --registration-enabled false \
    --output none
fi

private_endpoint_nic=$(az network private-endpoint show \
  --ids "$private_endpoint_id" \
  --query networkInterfaces[0].id --output tsv)

private_endpoint_ip=$(az network nic show \
  --ids "$private_endpoint_nic" \
  --query ipConfigurations[0].privateIPAddress --output tsv)

if az network private-dns record-set a show \
  --resource-group "$dns_zone_resource_group" \
  --zone-name "$dns_zone_name" \
  --name "$dns_record_name" --output none 2>/dev/null; then
  printf 'The private DNS record already exists; review it instead of overwriting it.\n' >&2
  exit 3
fi

az network private-dns record-set a create \
  --resource-group "$dns_zone_resource_group" \
  --zone-name "$dns_zone_name" \
  --name "$dns_record_name" \
  --output none

az network private-dns record-set a add-record \
  --resource-group "$dns_zone_resource_group" \
  --zone-name "$dns_zone_name" \
  --record-set-name "$dns_record_name" \
  --ipv4-address "$private_endpoint_ip" \
  --output none

az fileshare update \
  --name "$FILE_SHARE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --public-network-access Disabled \
  --output none

printf '%s\n' \
  'AZURE_NFS_SHARE_CREATED' \
  'PRIVATE_ENDPOINT_READY' \
  'PRIVATE_DNS_READY' \
  'PUBLIC_NETWORK_DISABLED'