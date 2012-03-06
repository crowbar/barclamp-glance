#
# Cookbook Name:: glance
# Recipe:: setup
#

include_recipe "#{@cookbook_name}::common"

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

  admin_token = "-I #{keystone["keystone"]["admin"]["username"]}"
  admin_token = "#{admin_token} -K #{keystone["keystone"]["admin"]["password"]}"
  admin_token = "#{admin_token} -T #{keystone["keystone"]["admin"]["tenant"]}"
else
  admin_token = ""
end

my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
port = node["glance"]["api"]["bind_port"]

glance_args = "-H #{my_ipaddress} -p #{port} #{admin_token}"

#
# Download and install AMIs
#
# XXX: This is not generic and only works with this one image.
# If the json file changes, we need to update this procedure.
#
(node[:glance][:images] or []).each do |image|
  #get the filename of the image
  filename = image.split('/').last
  bash "upload_image #{filename}" do
    code <<-EOH
mkdir -p tmp_dir
tar -zxf #{filename} -C tmp_dir/
glance #{glance_args} index # Make sure database is running
glance #{glance_args} add name="ubuntu-11.04-kernel" disk_format=aki container_format=aki is_public='True' < tmp_dir/natty-server-cloudimg-amd64-vmlinuz-virtual
glance #{glance_args} add name="ubuntu-11.04-initrd" disk_format=ari container_format=ari is_public='True' < tmp_dir/natty-server-cloudimg-amd64-loader
glance #{glance_args} add name="ubuntu-11.04-server" disk_format=ami container_format=ami kernel_id=1 ramdisk_id=2 is_public='True' < tmp_dir/natty-server-cloudimg-amd64.img
rm -rf tmp_dir
EOH
    cwd "#{node[:glance][:working_directory]}/raw_images"
    action :nothing
  end
  remote_file image do
    source image
    path "#{node[:glance][:working_directory]}/raw_images/#{filename}"
    action :create_if_missing
    notifies :run, "bash[upload_image #{filename}]", :immediately
  end
end

