#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

if node[:glance][:use_gitrepo]
  glance_path = "/opt/glance"
  venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
  venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil
end

keystone_settings = GlanceHelper.keystone_settings(node)

if node[:glance][:use_gitrepo]
  pfs_and_install_deps "keystone" do
    cookbook "keystone"
    cnode keystone
    path File.join(glance_path,"keystone")
    virtualenv venv_path
  end
end

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :bind_host => registry_bind_host,
      :bind_port => registry_bind_port,
      :keystone_settings => keystone_settings
  )
end

bash "Set glance version control" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "exit 0"
  notifies :run, "bash[Sync glance db]", :immediately
  only_if "#{venv_prefix}glance-manage version_control 0", :user => node[:glance][:user], :group => node[:glance][:group]
  action :run
end

bash "Sync glance db" do
  user node[:glance][:user]
  group node[:glance][:group]
  code "#{venv_prefix}glance-manage db_sync"
  action :nothing
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
