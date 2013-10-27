#
# Cookbook Name:: glance
# Recipe:: setup
#

include_recipe "#{@cookbook_name}::common"

if node[:glance][:use_gitrepo]
  glance_path = "/opt/glance"
  venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
  venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil
end

directory "#{node[:glance][:working_directory]}/raw_images" do
  action :create
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

  glance_args = "--os-username #{keystone["keystone"]["admin"]["username"]}"
  glance_args = "#{glance_args} --os-password #{keystone["keystone"]["admin"]["password"]}"
  glance_args = "#{glance_args} --os-tenant-name #{keystone["keystone"]["admin"]["tenant"]}"
  glance_args = "#{glance_args} --os-auth-url #{keystone["keystone"]["api"]["protocol"]}://#{keystone[:fqdn]}:#{keystone["keystone"]["api"]["api_port"]}/v2.0"
  glance_args = "#{glance_args} --os-endpoint-type internalURL"
else
  my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  port = node["glance"]["api"]["bind_port"]

  glance_args = "-H #{my_ipaddress} -p #{port}"
end
my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address

# temporary hack to manage docker registry
#
# setup docker
# Author: Judd Maltin

if node.platform == "ubuntu"
  # basic package installation
  package "lxc-docker" do
    action :install
  end

  service "docker" do
    action :start
  end

  directory "#{node[:glance][:working_directory]}/docker_images" do
    action :create
  end

  # get docker images
  (node[:glance][:docker_images] or []).each do |image|
    #get the filename of the image
    imagename = image.split('/').last
    imagename = imagename.split('.').first
    execute "glance: docker: importing images" do
      command "docker import #{image} #{imagename}"
      not_if "docker images | grep -qw \"^#{imagename}\""
    end
  end

  # NOTE: OS_GLANCE_URL = GLANCE API URL
  os_glance_url="#{node[:glance][:api][:protocol]}://#{my_ipaddress}:#{node[:glance][:api][:bind_port]}"
  docker_registry_port_public = node[:glance][:docker_registry_port] - 1
  docker_registry_url="#{node[:glance][:api][:protocol]}://#{my_ipaddress}:#{docker_registry_port_public}"
  docker_reg_run_cmd =  %{ docker run -d -p #{docker_registry_port_public}:#{node[:glance][:docker_registry_port]} \
-e SETTINGS_FLAVOR=openstack \
-e OS_USERNAME=#{keystone["keystone"]["admin"]["username"]} \
-e OS_PASSWORD="#{keystone["keystone"]["admin"]["password"]}" \
-e OS_TENANT_NAME="#{keystone["keystone"]["admin"]["tenant"]}" \
-e OS_AUTH_URL="#{keystone["keystone"]["api"]["protocol"]}://#{keystone[:fqdn]}:#{keystone["keystone"]["api"]["api_port"]}/v2.0" \
-e OS_GLANCE_URL="#{os_glance_url}" \
docker-registry ./docker-registry/run.sh }

  ## Start the Docker registry container
  log "executing: #{docker_reg_run_cmd}"
  log "docker_registry_url: #{docker_registry_url}"
  execute "glance: start docker registry #{docker_registry_url}" do
    command "#{docker_reg_run_cmd}"
    not_if "/usr/bin/curl -s #{docker_registry_url} >> /dev/null"
  end


  ## Did the registry really start?
  execute "glance: wait for docker registry to start" do
    command "while ! curl -s #{docker_registry_url}; do sleep 1; done"
    timeout 20
  end

  ## Tag image if not already tagged
  docker_registry_for_tag="#{my_ipaddress}:#{docker_registry_port_public}"
  (node[:glance][:docker_images] or []).each do |image|
    #get the filename of the image
    imagename = image.split('/').last
    imagename = imagename.split('.').first
    next if imagename.eql?('docker-registry')
    docker_repository_url = docker_registry_for_tag + "/" + imagename
    execute "glance: docker: tagging images with repository name" do
      command "docker tag #{imagename} #{docker_repository_url}; docker push #{docker_repository_url} #{docker_repository_url}"
      not_if "docker images | grep -qw \"#{docker_repository_url}\""
    end
  end
  #execute "glance: docker: tag images with repository name" do
    #command "if ! docker images | grep ; then
  ##docker tag $DOCKER_IMAGE_NAME $DOCKER_REPOSITORY_NAME
  #if ! docker images | grep $DOCKER_REPOSITORY_NAME; then
  #docker tag $DOCKER_IMAGE_NAME $DOCKER_REPOSITORY_NAME
  #fi
  
  ## Make sure we copied the image in Glance
  glance_command = "glance #{glance_args} image-list "
  log "glance_command: #{glance_command}"
  execute "make sure docker images are in glance" do
    command "#{glance_command}"
  end

  # Push images into docker registry (and they'll show up in glance)
  #if ! is_set DOCKER_IMAGE ; then
  #docker push $DOCKER_REPOSITORY_NAME
  #fi
end
#
# Download and install AMIs
#
# XXX: This is not generic and only works with this one image.
# If the json file changes, we need to update this procedure.
#

(node[:glance][:images] or []).each do |image|
  #get the filename of the image
  filename = image.split('/').last
  remote_file image do
    source image
    path "#{node[:glance][:working_directory]}/raw_images/#{filename}"
    action :create_if_missing
    not_if do 
      ::File.exists?("#{node[:glance][:working_directory]}/raw_images/#{filename}.keep")
    end
  end
end
ruby_block "load glance images" do
  block do
    wait = true
    rawdir="#{node[:glance][:working_directory]}/raw_images"
    Dir.entries(rawdir).each do |name|
      next unless node[:glance][:images].map{|n|n.split('/').last}.member?(name)
      basename = name.split('-')[0..1].join('-')
      tmpdir = "#{rawdir}/#{basename}"
      Dir.mkdir("#{tmpdir}") unless File.exists?("#{tmpdir}")
      Chef::Log.info("Extracting #{name} into #{tmpdir}")
      ::Kernel.system("tar -zxf \"#{rawdir}/#{name}\" -C \"#{tmpdir}/\"")
      if wait
        ::Kernel.system("#{venv_prefix}glance #{glance_args} image-list")
        sleep 15
        wait = false
      end
      ids = Hash.new
      cmds = Hash.new
      # Yes, this is exceptionally stupid for now.  Eventually it will be smarter.
      [ ["kernel", "vmlinuz-virtual"],
        ["initrd", "loader" ],
        ["image", ".img"] ].each do |part|
        next unless image_part = Dir.glob("#{tmpdir}/*#{part[1]}").first
        cmd = "#{venv_prefix}glance #{glance_args} image-create --name #{basename}-#{part[0]} --public"
        case part[0]
        when "kernel" then cmd << " --disk-format aki --container-format aki"
        when "initrd" then cmd << " --disk-format ari --container-format ari"
        when "image"
          cmd << " --disk-format ami --container-format ami"
          cmd << " --property kernel_id=#{ids["kernel"]}" if ids["kernel"]
          cmd << " --property ramdisk_id=#{ids["initrd"]}" if ids["initrd"]
        end
        res = %x{#{venv_prefix}glance #{glance_args} image-list| grep #{basename}-#{part[0]} 2>&1}
        if res.nil? || res.empty?
          Chef::Log.info("Loading #{image_part} for #{basename}-#{part[0]}")
          res = %x{#{cmd} < "#{image_part}"}
        else
          Chef::Log.info("#{basename}-#{part[0]} already loaded.")
        end
        ids[part[0]] = res.match(/([0-9a-f]+-){4}[0-9a-f]+/)
      end
      ::Kernel.system("rm -rf \"#{tmpdir}\"")
      File.truncate("#{rawdir}/#{name}",0)
      File.rename("#{rawdir}/#{name}","#{rawdir}/#{name}.keep")
    end
  end
end

