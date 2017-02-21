case node[:platform]
when "suse", "redhat", "centos"
  default["glance"]["services"] = {
    "server" => ["openstack-glance-api", "openstack-glance-registry"]
  }
end
