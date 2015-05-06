#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)
network_settings = GlanceHelper.network_settings(node)

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :bind_host => network_settings[:registry][:bind_host],
      :bind_port => network_settings[:registry][:bind_port],
      :keystone_settings => keystone_settings,
      :rabbit_settings => fetch_rabbitmq_settings
  )
end

crowbar_pacemaker_sync_mark "wait-glance_db_sync"

execute "glance-manage db sync" do
  user node[:glance][:user]
  group node[:glance][:group]
  # We know the glance-api.conf file is not updated yet, so forcefully ignore it
  command "glance-manage --config-file \"#{node[:glance][:registry][:config_file]}\" db sync"
  # We only do the sync the first time, and only if we're not doing HA or if we
  # are the founder of the HA cluster (so that it's really only done once).
  only_if { !node[:glance][:db_synced] && (!node[:glance][:ha][:enabled] || CrowbarPacemakerHelper.is_cluster_founder?(node)) }
end

# We want to keep a note that we've done db_sync, so we don't do it again.
# If we were doing that outside a ruby_block, we would add the note in the
# compile phase, before the actual db_sync is done (which is wrong, since it
# could possibly not be reached in case of errors).
ruby_block "mark node for glance db_sync" do
  block do
    node[:glance][:db_synced] = true
    node.save
  end
  action :nothing
  subscribes :create, "execute[glance-manage db sync]", :immediately
end

crowbar_pacemaker_sync_mark "create-glance_db_sync"

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
