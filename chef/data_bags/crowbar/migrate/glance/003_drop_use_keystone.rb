def upgrade ta, td, a, d
  a.delete 'use_keystone'
  return a, d
end

def downgrade ta, td, a, d
  a['use_keystone'] = ta['use_keystone']
  return a, d
end
