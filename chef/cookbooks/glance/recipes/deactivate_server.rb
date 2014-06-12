resource = "glance"
main_role = "server"

unless node["roles"].include?("#{resource}-#{main_role}")
  # HA part if node is in a cluster
  if File.exist?("/usr/sbin/crm")
    clone_resource = "cl-g-#{resource}"

    pacemaker_clone clone_resource do
      action [:stop, :delete]
      only_if "crm configure show #{clone_resource}"
    end

    node[resource]["services"][main_role].each do |name|
      name.gsub!("openstack-","")
      pacemaker_primitive name do
        action [:stop, :delete]
        only_if "crm configure show #{name}"
      end
    end
  else
    # Non HA part if service is on a standalone node
    node[resource]["services"][main_role].each do |name|
      service name do
        action [:stop, :disable]
      end
    end
  end
  node.delete(resource)

  node.save
end
