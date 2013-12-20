def upgrade ta, td, a, d
  a['rbd'] = {}
  a['rbd']['store_ceph_conf'] = '/etc/ceph/ceph.conf'
  a['rbd']['store_user'] = 'glance'
  a['rbd']['store_pool'] = 'images'
  return a, d
end

def downgrade ta, td, a, d
  a.delete('rbd')
  return a, d
end
