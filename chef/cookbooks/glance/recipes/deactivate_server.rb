unless node['roles'].include?('glance-server')
  node["glance"]["services"]["server"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node.delete('glance')
  node.save
end
