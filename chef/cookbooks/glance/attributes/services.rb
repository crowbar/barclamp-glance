case node["platform"]
when "suse"
  default["glance"]["services"] = {
    "server" => ["openstack-glance-api", "openstack-glance-registry"]
  }
end
