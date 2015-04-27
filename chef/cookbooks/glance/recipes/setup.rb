#
# Cookbook Name:: glance
# Recipe:: setup
#

include_recipe "#{@cookbook_name}::common"

directory "#{node[:glance][:working_directory]}/raw_images" do
  action :create
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

glance_args = "--os-username '#{keystone_settings["admin_user"]}'"
glance_args = "#{glance_args} --os-password '#{keystone_settings["admin_password"]}'"
glance_args = "#{glance_args} --os-tenant-name '#{keystone_settings["admin_tenant"]}'"
glance_args = "#{glance_args} --os-auth-url '#{keystone_settings["internal_auth_url"]}'"
glance_args = "#{glance_args} --os-endpoint-type internalURL"
glance_args = "#{glance_args} --os-region-name '#{keystone_settings["endpoint_region"]}'"

#
# Download and install AMIs
#
# XXX: This is not generic and only works with this one image.
# If the json file changes, we need to update this procedure.
#

if %w(redhat centos suse).include?(node.platform)
  package "python-glanceclient" do
    action :install
  end
end

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
        ::Kernel.system("glance #{glance_args} image-list")
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
        cmd = "glance #{glance_args} image-create --name #{basename}-#{part[0]} --public"
        case part[0]
        when "kernel" then cmd << " --disk-format aki --container-format aki"
        when "initrd" then cmd << " --disk-format ari --container-format ari"
        when "image"
          cmd << " --disk-format ami --container-format ami"
          cmd << " --property kernel_id=#{ids["kernel"]}" if ids["kernel"]
          cmd << " --property ramdisk_id=#{ids["initrd"]}" if ids["initrd"]
        end
        res = %x{glance #{glance_args} image-list| grep #{basename}-#{part[0]} 2>&1}
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
  action :nothing
  subscribes :create, "execute[trigger-glance-load-images]", :delayed
end

# This is to trigger the above resource to run :delayed, so that they run at
# the end of the chef-client run, after the glance services have been restarted
# (in case of a config change)
execute "trigger-glance-load-images" do
  command "true"
  only_if { !node[:glance][:ha][:enabled] || CrowbarPacemakerHelper.is_cluster_founder?(node) }
end
