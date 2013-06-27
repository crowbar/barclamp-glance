#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

glance_path = "/opt/glance"
venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones.first
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
  keystone_protocol = keystone["keystone"]["api"]["protocol"]
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_address}")

  if node[:glance][:use_gitrepo]
    pfs_and_install_deps "keystone" do
      cookbook "keystone"
      cnode keystone
      path File.join(glance_path,"keystone")
      virtualenv venv_path
    end
  end

else
  keystone_protocol = ""
  keystone_address = ""
  keystone_token = ""
  keystone_service_port = ""
  keystone_service_tenant = ""
  keystone_service_user = ""
  keystone_service_password = ""
end

template node[:glance][:api][:config_file] do
  source "glance-api.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :keystone_protocol => keystone_protocol,
      :keystone_address => keystone_address,
      :keystone_admin_port => keystone_admin_port
      :keystone_service_port => keystone_service_port,
      :keystone_service_user => keystone_service_user,
      :keystone_service_password => keystone_service_password,
      :keystone_service_tenant => keystone_service_tenant
  )
end

bash "Set api glance version control" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "exit 0"
  notifies :run, "bash[Sync api glance db]", :immediately
  only_if "#{venv_prefix}glance-manage version_control 0", :user => node[:glance][:user], :group => node[:glance][:group]
  action :run
end

bash "Sync api glance db" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "#{venv_prefix}glance-manage db_sync"
  action :nothing
end

if node[:glance][:use_keystone]
  # If we let the service bind to all IPs, then the service is obviously usable
  # from the public network. Otherwise, the endpoint URL should use the unique
  # IP that will be listened on.
  if node[:glance][:api][:bind_open_address]
    endpoint_admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
    endpoint_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public").address
  else
    endpoint_admin_ip = node[:glance][:api][:bind_host]
    endpoint_public_ip = node[:glance][:api][:bind_host]
  end
  api_port = node["glance"]["api"]["bind_port"]

  keystone_register "register glance service" do
    protocol keystone_protocol
    host keystone_address
    port keystone_admin_port
    token keystone_token
    service_name "glance"
    service_type "image"
    service_description "Openstack Glance Service"
    action :add_service
  end

  keystone_register "register glance endpoint" do
    protocol keystone_protocol
    host keystone_address
    port keystone_admin_port
    token keystone_token
    endpoint_service "glance"
    endpoint_region "RegionOne"
    endpoint_publicURL "http://#{endpoint_public_ip}:#{api_port}/v1"
    endpoint_adminURL "http://#{endpoint_admin_ip}:#{api_port}/v1"
    endpoint_internalURL "http://#{endpoint_admin_ip}:#{api_port}/v1"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end

glance_service "api"

node[:glance][:monitor][:svcs] <<["glance-api"]

