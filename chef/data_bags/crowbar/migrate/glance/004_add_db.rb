def upgrade ta, td, a, d
  a['db'] = ta['db']

  # we use a class variable to set the same password in the proposal and in the
  # role; we also try to import the database password from the node that was
  # deployed
  unless defined?(@@glance_db_password)
    service = ServiceObject.new "fake-logger"
    @@glance_db_password = service.random_password
  end

  Chef::Search::Query.new.search(:node) do |node|
    dirty = false
    unless (node[:glance][:db][:password] rescue nil).nil?
      unless node[:glance][:db][:password].empty?
        @@glance_db_password = node[:glance][:db][:password]
      end
      node[:glance][:db].delete('password')
      dirty = true
    end
    unless (node[:glance][:db][:database] rescue nil).nil?
      node[:glance][:db].delete('database')
      dirty = true
    end
    unless (node[:glance][:db][:user] rescue nil).nil?
      node[:glance][:db].delete('user')
      dirty = true
    end
    node.save if dirty
  end

  # old value that was hard-coded
  a['db']['database'] = "glancedb"
  a['db']['password'] = @@glance_db_password

  return a, d
end

def downgrade ta, td, a, d
  a.delete('db')
  return a, d
end
