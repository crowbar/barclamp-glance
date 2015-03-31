def upgrade ta, td, a, d
  a['rbd']['store_admin_keyring'] = ta['rbd']['store_admin_keyring']
  return a, d
end

def downgrade ta, td, a, d
  a['rbd'].delete('store_admin_keyring')
  return a, d
end
