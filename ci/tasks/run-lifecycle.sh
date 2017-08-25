#!/usr/bin/env bash

set -e

: ${AZURE_ENVIRONMENT:?}
: ${AZURE_SUBSCRIPTION_ID:?}
: ${AZURE_TENANT_ID:?}
: ${AZURE_CLIENT_ID:?}
: ${AZURE_CLIENT_SECRET:?}
: ${AZURE_STORAGE_ACCOUNT_NAME:?}
: ${AZURE_DEFAULT_GROUP_NAME:?}
: ${AZURE_ADDITIONAL_GROUP_NAME:?}
: ${AZURE_VNET_NAME_FOR_LIFECYCLE:?}
: ${AZURE_BOSH_SUBNET_NAME:?}
: ${AZURE_BOSH_SECOND_SUBNET_NAME:?}
: ${SSH_PUBLIC_KEY:?}
: ${AZURE_DEFAULT_SECURITY_GROUP:?}
: ${AZURE_APP_NAME:?}
: ${AZURE_APPLICATION_GATEWAY_NAME:?}

export BOSH_AZURE_ENVIRONMENT=${AZURE_ENVIRONMENT}
export BOSH_AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
export BOSH_AZURE_TENANT_ID=${AZURE_TENANT_ID}
export BOSH_AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
export BOSH_AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
export BOSH_AZURE_DEFAULT_RESOURCE_GROUP_NAME=${AZURE_DEFAULT_GROUP_NAME}
export BOSH_AZURE_ADDITIONAL_RESOURCE_GROUP_NAME=${AZURE_ADDITIONAL_GROUP_NAME}
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME}
export BOSH_AZURE_VNET_NAME=${AZURE_VNET_NAME_FOR_LIFECYCLE}
export BOSH_AZURE_SUBNET_NAME=${AZURE_BOSH_SUBNET_NAME}
export BOSH_AZURE_SECOND_SUBNET_NAME=${AZURE_BOSH_SECOND_SUBNET_NAME}
export BOSH_AZURE_SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export BOSH_AZURE_DEFAULT_SECURITY_GROUP=${AZURE_DEFAULT_SECURITY_GROUP}
export BOSH_AZURE_STEMCELL_ID="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
export BOSH_AZURE_APPLICATION_GATEWAY_NAME=${AZURE_APPLICATION_GATEWAY_NAME}

azure login --environment ${AZURE_ENVIRONMENT} --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}
azure config mode arm

export BOSH_AZURE_PRIMARY_PUBLIC_IP=$(azure network public-ip show ${AZURE_DEFAULT_GROUP_NAME} AzureCPICI-cf-lifecycle --json | jq '.ipAddress' -r)
export BOSH_AZURE_SECONDARY_PUBLIC_IP=$(azure network public-ip show ${AZURE_ADDITIONAL_GROUP_NAME} AzureCPICI-cf-lifecycle --json | jq '.ipAddress' -r)

export AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT_NAME}
export AZURE_STORAGE_ACCESS_KEY=$(azure storage account keys list ${AZURE_STORAGE_ACCOUNT_NAME} -g ${AZURE_DEFAULT_GROUP_NAME} --json | jq '.[0].value' -r)

# Always upload the latest stemcell for lifecycle test
tar -xf $(realpath stemcell/*.tgz) -C /tmp/
tar -xf /tmp/image -C /tmp/
azure storage blob upload --quiet --blobtype PAGE --file /tmp/root.vhd --container stemcell --blob ${BOSH_AZURE_STEMCELL_ID}.vhd

source /etc/profile.d/chruby.sh
chruby ${RUBY_VERSION}

export BOSH_AZURE_USE_MANAGED_DISKS=${AZURE_USE_MANAGED_DISKS}
pushd bosh-cpi-src/src/bosh_azure_cpi > /dev/null
  bundle install
  bundle exec rspec spec/integration/lifecycle_spec.rb
popd > /dev/null

# Only run migration test when AZURE_USE_MANAGED_DISKS is set to false initially
if [ "${AZURE_USE_MANAGED_DISKS}" == "false" ]; then
  unset BOSH_AZURE_USE_MANAGED_DISKS
  pushd bosh-cpi-src/src/bosh_azure_cpi > /dev/null
    bundle install
    bundle exec rspec spec/integration/managed_disks_migration_spec.rb
  popd > /dev/null
fi

# The azure_cpi test doesn't care whether managed disks are used. Only run it when AZURE_USE_MANAGED_DISKS is set to true
if [ "${AZURE_USE_MANAGED_DISKS}" == "true" ]; then
  export BOSH_AZURE_USE_MANAGED_DISKS=true
  pushd bosh-cpi-src/src/bosh_azure_cpi > /dev/null
    bundle install
    bundle exec rspec spec/integration/azure_cpi_spec.rb
  popd > /dev/null
fi
