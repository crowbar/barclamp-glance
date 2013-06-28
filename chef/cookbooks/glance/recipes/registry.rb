#
# Cookbook Name:: glance
# Recipe:: registry
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
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
  keystone_protocol = keystone["keystone"]["api"]["protocol"]
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_address}")
else
  keystone_protocol = ""
  keystone_address = ""
  keystone_token = ""
  keystone_service_port = ""
  keystone_service_tenant = ""
  keystone_service_user = ""
  keystone_service_password = ""
end

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
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

bash "Set registry glance version control" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "exit 0"
  notifies :run, "bash[Sync registry glance db]", :immediately
  only_if "#{venv_prefix}glance-manage version_control 0", :user => node[:glance][:user], :group => node[:glance][:group]
  action :run
end

bash "Sync registry glance db" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "#{venv_prefix}glance-manage db_sync"
  action :nothing
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
