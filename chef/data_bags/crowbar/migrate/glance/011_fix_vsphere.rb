def upgrade ta, td, a, d
  a['vsphere']['datacenter_path'] = ta['vsphere']['datacenter_path']
  a['vsphere']['store_image_dir'] = ta['vsphere']['store_image_dir']
  return a, d
end

def downgrade ta, td, a, d
  a['vsphere'].delete('datacenter_path')
  a['vsphere'].delete('store_image_dir')
  return a, d
end
