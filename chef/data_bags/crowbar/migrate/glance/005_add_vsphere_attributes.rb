def upgrade ta, td, a, d
  a['vsphere'] = ta['vsphere']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('vsphere')
  return a, d
end
