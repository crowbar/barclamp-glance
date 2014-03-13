def upgrade ta, td, a, d
  a['db'] = ta['db']
  service = ServiceObject.new "fake-logger"
  # old value that was hard-coded
  a['db']['database'] = "glancedb"
  a['db']['password'] = service.random_password
  return a, d
end

def downgrade ta, td, a, d
  a.delete('db')
  return a, d
end
