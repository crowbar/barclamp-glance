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

  key_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address
  admin_token = "-I #{keystone["keystone"]["admin"]["username"]}"
  admin_token = "#{admin_token} -K #{keystone["keystone"]["admin"]["password"]}"
  admin_token = "#{admin_token} -T #{keystone["keystone"]["admin"]["tenant"]}"
  admin_token = "#{admin_token} -N http://#{key_ip}:#{keystone["keystone"]["api"]["api_port"]}/v2.0"
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

# crate empty list of images and processed_images if nil
node[:glance][:processed_images] ||= []
node[:glance][:images] ||= []

images = node[:glance][:images] - node[:glance][:processed_images]
raw_images = []

rawdir="#{node[:glance][:working_directory]}/raw_images"

images.each do |url|
  filename = url.split("/").last
  remote_file "#{rawdir}/#{filename}" do
    source url
    action :create_if_missing
  end
  raw_images << url
end

ruby_block "load glance images" do
  block do
    raw_images.each do |url|
      image = url.split("/").last
      basename = image.split('-')[0..1].join('-')
      puts "Basename: #{basename}"
      FileUtils.rm_rf "#{rawdir}/#{basename}"
      FileUtils.mkdir "#{rawdir}/#{basename}"
      ::Kernel.system "tar -zxf \"#{rawdir}/#{image}\" -C \"#{rawdir}/#{basename}/\""

      # wait about 15 seconds for check of accessible glance service
      Timeout::timeout(15) { ::Kernel.system "glance #{glance_args} details > /dev/null" }

      ids = Hash.new
      [["kernel", "vmlinuz-virtual"],["initrd", "loader" ],["image", ".img"]].each do |part|
        next unless image_part = Dir.glob("#{rawdir}/#{basename}/*#{part[1]}").first
        res = %x{glance #{glance_args} image-list --name #{basename}-#{part[0]} > /dev/null 2>&1}.strip
        if res.nil? || res.empty?
          # image not exists in glance
          Chef::Log.info "Loading #{image_part} for #{basename}-#{part[0]}"
          cmd = "glance #{glance_args} image-create --name #{basename}-#{part[0]} --is-public True"
          case part[0]
            when "kernel" then cmd << " --disk-format aki --container-format aki"
            when "initrd" then cmd << " --disk-format ari --container-format ari"
            when "image"
              cmd << " --disk-format ami --container-format ami"
              cmd << " --property kernel_id=#{ids["kernel"]}" if ids["kernel"]
              cmd << " --property ramdisk_id=#{ids["initrd"]}" if ids["initrd"]
          end
          res = %x{#{cmd} < "#{image_part}"}
          ids[part[0]] = res.match(/([0-9a-f]+-){4}[0-9a-f]+/)
          Chef::Log.info "Loading complete"
        else
          # image already exists in glance
          Chef::Log.info "Skip #{basename}-#{part[0]}, already loaded."
        end
      end
      FileUtils.rm_rf "#{rawdir}/#{basename}"
      node[:glance][:processed_images] << url
    end
  end
  retries 3
  # defore retry wait about 60 seconds
  retry_delay 60
end
