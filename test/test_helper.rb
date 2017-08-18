require 'redis'

def redis_cleanup(prefix)
  r = Redis.new
  r.keys("#{prefix}*").each { |k| r.del(k) }
end
