#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

if node[:keystone][:api][:protocol] == "https"
  include_recipe "apache2"
  include_recipe "apache2::mod_ssl"
  include_recipe "apache2::mod_wsgi"
end

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_host = keystone[:fqdn]
  keystone_protocol = keystone["keystone"]["api"]["protocol"]
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_host}")
else
  keystone_host = ""
  keystone_token = ""
end

template node[:glance][:api][:config_file] do
  source "glance-api.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0640
end

template node[:glance][:api][:paste_ini] do
  source "glance-api-paste.ini.erb"
  owner node[:glance][:user]
  group "root"
  mode 0640
  variables(
    :keystone_protocol => keystone_protocol,
    :keystone_host => keystone_host,
    :keystone_auth_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_admin_port => keystone_admin_port
  )
end

if node[:glance][:use_keystone]
  my_admin_host = node[:fqdn]
  my_public_host = 'public.'+node[:fqdn]
  api_protocol = node[:glance][:api][:protocol]
  api_port = node["glance"]["api"]["bind_port"]

  keystone_register "glance api wakeup keystone" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    action :wakeup
  end

  keystone_register "register glance user" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    user_password keystone_service_password
    tenant_name keystone_service_tenant
    action :add_user
  end

  keystone_register "give glance user access" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    tenant_name keystone_service_tenant
    role_name "admin"
    action :add_access
  end

  keystone_register "register glance service" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    service_name "glance"
    service_type "image"
    service_description "Openstack Glance Service"
    action :add_service
  end

  keystone_register "register glance endpoint" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    endpoint_service "glance"
    endpoint_region "RegionOne"
    #endpoint_publicURL "http://#{my_public_host}:#{api_port}/v1"
    # We use my_admin_ip here as public_ip because all other services
    # query the public_ip for the 'image' endpoint in keystone's endpoint
    # catalog. All OpenStack services are in the admin network anyway
    # and can thus query glance without compromising security (contrary
    # to making glance listen on all interfaces):
    endpoint_publicURL "#{api_protocol}://#{my_admin_host}:#{api_port}/v1"
    endpoint_adminURL "#{api_protocol}://#{my_admin_host}:#{api_port}/v1"
    endpoint_internalURL "#{api_protocol}://#{my_admin_host}:#{api_port}/v1"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end


if node[:glance][:api][:protocol] == "https"
  Chef::Log.info("Configuring Glance to use SSL via Apache2+mod_wsgi")

  service "glance-api" do
    service_name "openstack-glance-api" if node.platform == "suse"
    action [:disable, :stop]
  end

  # Prepare Apache2 SSL vhost template:
  template "#{node[:apache][:dir]}/sites-available/openstack-glance.conf" do
    if node.platform == "suse"
      path "#{node[:apache][:dir]}/vhosts.d/openstack-glance.conf"
    end
    source "glance-apache-ssl.conf.erb"
    mode 0644
    if ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/openstack-glance.conf") or node.platform == "suse"
      notifies :reload, resources(:service => "apache2")
    end
  end

  apache_site "openstack-glance.conf" do
    enable true
  end

  template "/etc/logrotate.d/openstack-glance" do
    source "glance.logrotate.erb"
    mode 0644
    owner "root"
    group "root"
  end
else
  # Remove potentially left-over Apache2 config files:
  if node.platform == "suse"
    vhost_config = "#{node[:apache][:dir]}/vhosts.d/openstack-glance.conf"
  else
    vhost_config = "#{node[:apache][:dir]}/sites-available/openstack-glance.conf"
  end

  if ::File.exist?(vhost_config)
    apache_site "openstack-glance.conf" do
      enable false
    end

    file vhost_config do
      action :delete
    end if node.platform != "suse"

    file "/etc/logrotate.d/openstack-glance" do
      action :delete
    end
  end
  # End of Apache2 vhost cleanup

  glance_service "api"
end

node[:glance][:monitor][:svcs] <<["glance-api"]

