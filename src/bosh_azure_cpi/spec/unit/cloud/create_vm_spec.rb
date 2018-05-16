require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#create_vm' do
    # Parameters
    let(:agent_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:stemcell_id) { "bosh-stemcell-xxx" }
    let(:light_stemcell_id) { "bosh-light-stemcell-xxx" }
    let(:resource_pool) { {'instance_type' => 'fake-vm-size'} }
    let(:networks_spec) { {} }
    let(:disk_locality) { double("disk locality") }
    let(:environment) { double("environment") }
    let(:default_resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:virtual_network_name) { "fake-virual-network-name" }
    let(:location) { "fake-location" }
    let(:vnet) { {:location => location} }
    let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }
    let(:network) { instance_double(Bosh::AzureCloud::ManualNetwork) }
    let(:network_configurator) { double("network configurator") }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }

    before do
      allow(network_configurator).to receive(:networks).
        and_return([network])
      allow(network).to receive(:resource_group_name).
        and_return(default_resource_group_name)
      allow(network).to receive(:virtual_network_name).
        and_return(virtual_network_name)
      allow(client2).to receive(:get_virtual_network_by_name).
        with(default_resource_group_name, virtual_network_name).
        and_return(vnet)
      allow(telemetry_manager).to receive(:monitor).
        with('create_vm', id: agent_id, extras: {'instance_type' => 'fake-vm-size'}).
        and_call_original
    end

    context 'when vnet is not found' do
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties, networks_spec).
          and_return(network_configurator)
        allow(client2).to receive(:get_virtual_network_by_name).
          with(default_resource_group_name, virtual_network_name).
          and_return(nil)
      end

      it 'should raise an error' do
        expect {
          cloud.create_vm(
            agent_id,
            stemcell_id,
            resource_pool,
            networks_spec,
            disk_locality,
            environment
          )
        }.to raise_error(/Cannot find the virtual network/)
      end
    end

    context 'when the location in the global configuration is different from the vnet location' do
      let(:cloud_properties_with_location) { mock_cloud_properties_merge({'azure'=>{'location'=>"location-other-than-#{location}"}}) }
      let(:cloud_with_location) { mock_cloud(cloud_properties_with_location) }
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(cloud_properties_with_location['azure'], networks_spec).
          and_return(network_configurator)
        allow(client2).to receive(:get_virtual_network_by_name).
          with(default_resource_group_name, virtual_network_name).
          and_return(vnet)
      end

      it 'should raise an error' do
        expect {
          cloud_with_location.create_vm(
            agent_id,
            stemcell_id,
            resource_pool,
            networks_spec,
            disk_locality,
            environment
          )
        }.to raise_error(/The location in the global configuration `location-other-than-#{location}' is different from the location of the virtual network `#{location}'/)
      end
    end

    context 'when use_managed_disks is not set' do
      let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
      let(:instance_id_string) { "fake-instance-id" }
      let(:vm_params) {
        {
          :name => "fake-vm-name"
        }
      }

      let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
      let(:storage_account) {
        {
          :id => "foo",
          :name => storage_account_name,
          :location => location,
          :provisioning_state => "bar",
          :account_type => "foo",
          :storage_blob_host => "fake-blob-endpoint",
          :storage_table_host => "fake-table-endpoint"
        }
      }

      before do
        allow(storage_account_manager).to receive(:get_storage_account_from_resource_pool).
          with(resource_pool, location).
          and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?).
          with(storage_account_name, stemcell_id).
          and_return(true)
        allow(stemcell_manager).to receive(:get_stemcell_info).
          with(storage_account_name, stemcell_id).
          and_return(stemcell_info)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties, networks_spec).
          and_return(network_configurator)

        allow(Bosh::AzureCloud::InstanceId).to receive(:create).
          with(default_resource_group_name, agent_id, storage_account_name).
          and_return(instance_id)
        allow(instance_id).to receive(:to_s).
          and_return(instance_id_string)
      end

      context 'when everything is OK' do
        context 'and a heavy stemcell is used' do
          it 'should create the VM' do
            expect(vm_manager).to receive(:create).
              with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
              and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(stemcell_manager).to receive(:get_stemcell_info)
            expect(light_stemcell_manager).not_to receive(:has_stemcell?)
            expect(light_stemcell_manager).not_to receive(:get_stemcell_info)

            expect(
              cloud.create_vm(
                agent_id,
                stemcell_id,
                resource_pool,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id_string)
          end
        end

        context 'and a light stemcell is used' do
          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).
              with(location, light_stemcell_id).
              and_return(true)
            allow(light_stemcell_manager).to receive(:get_stemcell_info).
              with(light_stemcell_id).
              and_return(stemcell_info)
          end

          it 'should create the VM' do
            expect(vm_manager).to receive(:create).
              with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
              and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(light_stemcell_manager).to receive(:has_stemcell?)
            expect(light_stemcell_manager).to receive(:get_stemcell_info)
            expect(stemcell_manager).not_to receive(:get_stemcell_info)

            expect(
              cloud.create_vm(
                agent_id,
                light_stemcell_id,
                resource_pool,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id_string)
          end
        end

        context 'when resource group is specified' do
          let(:resource_group_name) { 'fake-resource-group-name' }
          let(:resource_pool) {
            {
              'instance_type' => 'fake-vm-size',
              'resource_group_name' => resource_group_name
            }
          }

          it 'should create the VM in the specified resource group' do
            expect(Bosh::AzureCloud::InstanceId).to receive(:create).
              with(resource_group_name, agent_id, storage_account_name).
              and_return(instance_id)
            expect(vm_manager).to receive(:create).
              with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
              and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(stemcell_manager).to receive(:get_stemcell_info)
            expect(light_stemcell_manager).not_to receive(:has_stemcell?)
            expect(light_stemcell_manager).not_to receive(:get_stemcell_info)

            expect(
              cloud.create_vm(
                agent_id,
                stemcell_id,
                resource_pool,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id_string)
          end
        end
      end

      context 'when availability_zone is specified' do
        let(:resource_pool) {
          { 'availability_zone' => 'fake-az',
            'instance_type' => 'fake-vm-size'
          }
        }

        it 'should raise an error' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error("Virtual Machines deployed to an Availability Zone must use managed disks")
        end
      end

      context 'when stemcell_id is invalid' do
        before do
          allow(stemcell_manager).to receive(:has_stemcell?).
            with(storage_account_name, stemcell_id).
            and_return(false)
        end

        it 'should raise an error' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error("Given stemcell `#{stemcell_id}' does not exist")
        end
      end

      context 'when network configurator fails' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
            and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error StandardError
        end
      end

      context 'when new vm is not created' do
        before do
          allow(vm_manager).to receive(:create).and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error StandardError
        end
      end

      context 'when registry fails to update' do
        before do
          allow(vm_manager).to receive(:create)
          allow(registry).to receive(:update_settings).and_raise(StandardError)
        end

        it 'deletes the vm' do
          expect(vm_manager).to receive(:delete).with(instance_id)

          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error(StandardError)
        end
      end
    end

    context 'when use_managed_disks is set' do
      let(:instance_id) { instance_double(Bosh::AzureCloud::InstanceId) }
      let(:instance_id_string) { "fake-instance-id" }
      let(:vm_params) {
        {
          :name => "fake-vm-name"
        }
      }

      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties_managed, networks_spec).
          and_return(network_configurator)

        allow(Bosh::AzureCloud::InstanceId).to receive(:create).
          with(default_resource_group_name, agent_id).
          and_return(instance_id)
        allow(instance_id).to receive(:to_s).
          and_return(instance_id_string)
      end

      context "when instance_type is not provided" do
        let(:resource_pool) { {} }

        it "should raise an error" do
          expect(client2).not_to receive(:delete_virtual_machine)
          expect(client2).not_to receive(:delete_network_interface)
          expect(client2).to receive(:list_network_interfaces_by_keyword).with(resource_group_name, vm_name).and_return([])
          expect(client2).to receive(:get_public_ip_by_name).
            with(resource_group_name, vm_name).
            and_return({ :ip_address => "public-ip" })
          expect(client2).to receive(:delete_public_ip).with(resource_group_name, vm_name)

          expect {
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error /missing required cloud property `instance_type'/
        end
      end

      context 'when it failed to get the user image info' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
            with(azure_properties_managed, networks_spec).
            and_return(network_configurator)
          allow(stemcell_manager2).to receive(:get_user_image_info).and_raise(StandardError)
        end

        it 'should raise an error' do
          expect {
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error(/Failed to get the user image information for the stemcell `#{stemcell_id}'/)
        end
      end

      context 'when a heavy stemcell is used' do
        before do
          allow(stemcell_manager2).to receive(:get_user_image_info).
            and_return(stemcell_info)
        end

        it 'should create the VM' do
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id_string)
        end
      end

      context 'when a light stemcell is used' do
        before do
          allow(light_stemcell_manager).to receive(:has_stemcell?).
            with(location, light_stemcell_id).
            and_return(true)
          allow(light_stemcell_manager).to receive(:get_stemcell_info).
            with(light_stemcell_id).
            and_return(stemcell_info)
        end

        it 'should create the VM' do
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(light_stemcell_manager).to receive(:has_stemcell?)
          expect(light_stemcell_manager).to receive(:get_stemcell_info)

          expect(
            managed_cloud.create_vm(
              agent_id,
              light_stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id_string)
        end
      end

      context 'when resource group is specified' do
        let(:resource_group_name) { 'fake-resource-group-name' }
        let(:resource_pool) {
          {
            'instance_type' => 'fake-vm-size',
            'resource_group_name' => resource_group_name
          }
        }

        before do
          allow(stemcell_manager2).to receive(:get_user_image_info).
            and_return(stemcell_info)
        end

        it 'should create the VM in the specified resource group' do
          expect(Bosh::AzureCloud::InstanceId).to receive(:create).
            with(resource_group_name, agent_id).
            and_return(instance_id)
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id_string)
        end
      end
    end
  end
end
