#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_address = keystone.address.addr
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_address}")
else
  keystone_address = ""
  keystone_token = ""
end

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
  variables(
    :keystone_address => keystone_address,
    :keystone_auth_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_admin_port => keystone_admin_port
  )
end

template node[:glance][:registry][:paste_ini] do
  source "glance-registry-paste.ini.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
  variables(
    :keystone_address => keystone_address,
    :keystone_auth_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_admin_port => keystone_admin_port
  )
end

bash "Set registry glance version control" do
  code "exit 0"
  notifies :run, "bash[Sync registry glance db]", :immediately
  only_if "glance-manage version_control 0"
  action :run
end

bash "Sync registry glance db" do
  code "glance-manage db_sync"
  action :nothing
end

if node[:glance][:use_keystone]
  my_admin_ip = node.address.addr
  my_public_ip = node.address("public").addr
  api_port = node["glance"]["api"]["bind_port"]

  keystone_register "glance registry wakeup keystone" do
    host keystone_address
    port keystone_admin_port
    token keystone_token
    action :wakeup
  end

  keystone_register "register glance user" do
    host keystone_address
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    user_password keystone_service_password
    tenant_name keystone_service_tenant
    action :add_user
  end

  keystone_register "give glance user access" do
    host keystone_address
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    tenant_name keystone_service_tenant
    role_name "admin"
    action :add_access
  end
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
