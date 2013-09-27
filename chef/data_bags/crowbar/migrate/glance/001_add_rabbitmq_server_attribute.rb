def upgrade ta, td, a, d
  a['rabbitmq_instance'] = 'default'
  return a, d
end

def downgrade ta, td, a, d
  a.delete('rabbitmq_instance')
  return a, d
end
