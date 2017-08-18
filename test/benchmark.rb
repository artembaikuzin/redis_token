require_relative 'test_helper'

require 'msgpack'
require 'redis_token'
require 'benchmark/ips'
require 'redis'

# Marshal vs MessagePack serialization comparison:
#
# create
# Warming up --------------------------------------
#              Marshal   883.000  i/100ms
#          MessagePack   890.000  i/100ms
# Calculating -------------------------------------
#              Marshal      8.861k (± 4.2%) i/s -     45.033k in   5.091600s
#          MessagePack      9.145k (± 1.0%) i/s -     46.280k in   5.060910s
#
# Comparison:
#          MessagePack:     9145.5 i/s
#              Marshal:     8861.1 i/s - same-ish: difference falls within error
#
# get
# Warming up --------------------------------------
#              Marshal     1.649k i/100ms
#          MessagePack     1.641k i/100ms
# Calculating -------------------------------------
#              Marshal     16.783k (± 1.0%) i/s -     84.099k in   5.011348s
#          MessagePack     16.714k (± 1.1%) i/s -     83.691k in   5.007984s
#
# Comparison:
#              Marshal:    16783.5 i/s
#          MessagePack:    16713.5 i/s - same-ish: difference falls within error
#

class MsgPackSerializer
  def pack(value)
    MessagePack.pack(value)
  end

  def unpack(value)
    MessagePack.unpack(value)
  end
end

PREFIX = 'rt.ben.'

native_marshal = RedisToken.new(prefix: PREFIX)
msgpack_marshal = RedisToken.new(prefix: PREFIX).use(MsgPackSerializer)


def create(instance)
  instance.create('client.1')
end

def get(instance)
  instance.get(SecureRandom.hex(16))
end

puts 'create'
Benchmark.ips do |x|
  x.report('Marshal') { create(native_marshal) }
  x.report('MessagePack') { create(msgpack_marshal) }
  x.compare!
end

puts 'get'
Benchmark.ips do |x|
  x.report('Marshal') { get(native_marshal) }
  x.report('MessagePack') { get(msgpack_marshal) }
  x.compare!
end

redis_cleanup(PREFIX)
