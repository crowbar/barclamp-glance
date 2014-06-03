def upgrade ta, td, a, d
  a.delete('image_cache_grace_period')
  a.delete('notifier_strategy')
  return a, d
end

def downgrade ta, td, a, d
  a['image_cache_grace_period'] = 3600
  a['notifier_strategy'] = 'noop'
  return a, d
end
