#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

if node[:glance][:use_gitrepo]
  glance_path = "/opt/glance"
  venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
  venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil
end

if node.platform == "ubuntu"
 package "qemu-utils"
end

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones.first
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
  keystone_protocol = ""
  keystone_host = ""
  keystone_token = ""
  keystone_service_port = ""
  keystone_service_tenant = ""
  keystone_service_user = ""
  keystone_service_password = ""
end

if node[:glance][:api][:protocol] == 'https'
  if node[:glance][:ssl][:generate_certs]
    package "openssl"
    ruby_block "generate_certs for glance" do
      block do
        unless ::File.exists? node[:glance][:ssl][:certfile] and ::File.exists? node[:glance][:ssl][:keyfile]
          require "fileutils"

          Chef::Log.info("Generating SSL certificate for glance...")

          [:certfile, :keyfile].each do |k|
            dir = File.dirname(node[:glance][:ssl][k])
            FileUtils.mkdir_p(dir) unless File.exists?(dir)
          end

          # Generate private key
          %x(openssl genrsa -out #{node[:glance][:ssl][:keyfile]} 4096)
          if $?.exitstatus != 0
            message = "SSL private key generation failed"
            Chef::Log.fatal(message)
            raise message
          end
          FileUtils.chown "root", node[:glance][:group], node[:glance][:ssl][:keyfile]
          FileUtils.chmod 0640, node[:glance][:ssl][:keyfile]

          # Generate certificate signing requests (CSR)
          conf_dir = File.dirname node[:glance][:ssl][:certfile]
          ssl_csr_file = "#{conf_dir}/signing_key.csr"
          ssl_subject = "\"/C=US/ST=Unset/L=Unset/O=Unset/CN=#{node[:fqdn]}\""
          %x(openssl req -new -key #{node[:glance][:ssl][:keyfile]} -out #{ssl_csr_file} -subj #{ssl_subject})
          if $?.exitstatus != 0
            message = "SSL certificate signed requests generation failed"
            Chef::Log.fatal(message)
            raise message
          end

          # Generate self-signed certificate with above CSR
          %x(openssl x509 -req -days 3650 -in #{ssl_csr_file} -signkey #{node[:glance][:ssl][:keyfile]} -out #{node[:glance][:ssl][:certfile]})
          if $?.exitstatus != 0
            message = "SSL self-signed certificate generation failed"
            Chef::Log.fatal(message)
            raise message
          end

          File.delete ssl_csr_file  # Nobody should even try to use this
        end # unless files exist
      end # block
    end # ruby_block
  else # if generate_certs
    unless ::File.exists? node[:glance][:ssl][:certfile]
      message = "Certificate \"#{node[:glance][:ssl][:certfile]}\" is not present."
      Chef::Log.fatal(message)
      raise message
    end
    # we do not check for existence of keyfile, as the private key is allowed
    # to be in the certfile
  end # if generate_certs

  if node[:glance][:ssl][:cert_required] and !::File.exists? node[:glance][:ssl][:ca_certs]
    message = "Certificate CA \"#{node[:glance][:ssl][:ca_certs]}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
end

if node[:glance][:notifier_strategy] != "noop"
  rabbitmq_env_filter = " AND rabbitmq_config_environment:rabbitmq-config-#{node[:glance][:rabbitmq_instance]}"
  rabbits = search(:node, "roles:rabbitmq-server#{rabbitmq_env_filter}") || []
  if rabbits.length > 0
    rabbit = rabbits[0]
    rabbit = node if rabbit.name == node.name
  else
    rabbit = node
  end
  rabbit_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(rabbit, "admin").address

  rabbit_settings = {
    :address => rabbit_address,
    :port => rabbit[:rabbitmq][:port],
    :user => rabbit[:rabbitmq][:user],
    :password => rabbit[:rabbitmq][:password],
    :vhost => rabbit[:rabbitmq][:vhost]
  }
end

template node[:glance][:api][:config_file] do
  source "glance-api.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :keystone_protocol => keystone_protocol,
      :keystone_host => keystone_host,
      :keystone_admin_port => keystone_admin_port,
      :keystone_service_port => keystone_service_port,
      :keystone_service_user => keystone_service_user,
      :keystone_service_password => keystone_service_password,
      :keystone_service_tenant => keystone_service_tenant,
      :rabbit_settings => rabbit_settings
  )
end

if node[:glance][:use_keystone]

  my_admin_host = node[:fqdn]
  # For the public endpoint, we prefer the public name. If not set, then we
  # use the IP address except for SSL, where we always prefer a hostname
  # (for certificate validation).
  my_public_host = node[:crowbar][:public_name]
  if my_public_host.nil? or my_public_host.empty?
    unless node[:glance][:api][:protocol] == "https"
      my_public_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public").address
    else
      my_public_host = 'public.'+node[:fqdn]
    end
  end

  # If we let the service bind to all IPs, then the service is obviously usable
  # from the public network. Otherwise, the endpoint URL should use the unique
  # IP that will be listened on.
  if node[:glance][:api][:bind_open_address]
    endpoint_admin_ip = my_admin_host
    endpoint_public_ip = my_public_host
  else
    endpoint_admin_ip = node[:glance][:api][:bind_host]
    endpoint_public_ip = node[:glance][:api][:bind_host]
  end
  api_port = node["glance"]["api"]["bind_port"]
  glance_protocol = node[:glance][:api][:protocol]

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
    endpoint_publicURL "#{glance_protocol}://#{endpoint_public_ip}:#{api_port}"
    endpoint_adminURL "#{glance_protocol}://#{endpoint_admin_ip}:#{api_port}"
    endpoint_internalURL "#{glance_protocol}://#{endpoint_admin_ip}:#{api_port}"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end

glance_service "api"

node[:glance][:monitor][:svcs] <<["glance-api"]

