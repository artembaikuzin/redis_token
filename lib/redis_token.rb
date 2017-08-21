require 'redis_token/version'
require 'redis_token/serializers/native'

require 'redis'

require 'securerandom'
require 'time'

class RedisToken
  # Token lives 14 days by default
  DEFAULT_TTL = 14 * 24 * 60 * 60
  DEFAULT_PREFIX = 'tokens.'.freeze

  attr_reader :redis
  attr_accessor :default_ttl
  attr_accessor :prefix
  attr_reader :created_value

  # Create RedisToken instance
  #
  # Implicit redis instance creation (redis parameters can be passed in args):
  #   RedisToken.new(ttl: 5.days, prefix: 'project.tokens.', host: '127.0.0.1')
  #
  # Explicit redis instance injection:
  #   redis = Redis.new(host: '192.168.0.1', port: 33221)
  #   RedisToken.new(redis, ttl: 5.days, prefix: 'project.tokens.')
  #
  # @param [Hash] args
  # @option args [String] :prefix (DEFAULT_PREFIX) redis keys prefix (e.g. 'myproject.tokens.')
  # @option args [Integer] :ttl token time to live value (14 days by default)
  # @option args [Class] :serializer_class serialization class, see RedisToken::Serializers::Native, or #use method
  #
  # @return [RedisToken] a new RedisToken instance
  def initialize(args = {}, opts = {})
    @redis = if args.nil? || args.is_a?(Hash)
               init_params(args)
               Redis.new(args)
             else
               init_params(opts)
               args
             end
  end

  # Create a new token
  #
  # @param [String] owner owner of a token, e.g. 'client.1' or 'user-123'
  # @param [Hash] args
  # @option args [String] :token (SecureRandom.hex(16)) user defined token
  # @option args :payload
  # @option args [Integer] :ttl redefines the default ttl
  #
  # @return [String] a new token
  def create(owner, args = {})
    raise 'owner should be specified' unless owner

    token = args[:token] || generate_token
    value = { owner: owner, at: Time.now.to_i }

    payload = args[:payload]
    value[:payload] = payload if payload

    @created_value = value
    key_ttl = args[:ttl] || @default_ttl

    @redis.multi do |multi|
      multi.set(token_to_key(token), serializer.pack(value), ex: key_ttl)
      multi.set(token_to_owner(owner, token), nil, ex: key_ttl)
    end

    token
  end

  # Get value of a token and slide ttl
  #
  # @param [String] token
  # @param [Hash] args
  # @option args [Integer] :ttl
  # @option args [Boolean] :slide_expire (true) slide ttl of a token
  #
  # @return [Hash] value of a token
  def get(token, args = {})
    key = token_to_key(token)
    value = redis_get(key)
    return unless value
    return value if args[:slide_expire] === false

    key_ttl = args[:ttl] || @default_ttl

    @redis.multi do |multi|
      multi.expire(key, key_ttl)
      multi.expire(token_to_owner(hash_get(value, :owner), token), key_ttl)
    end

    value
  end

  # Set new payload of a token
  #
  # @param [String] token
  # @param [Hash] args
  # @option args [Integer] :ttl set new time to live value
  # @option args :payload new payload value
  #
  # @return [Boolean]
  def set(token, args = {})
    key = token_to_key(token)
    value = redis_get(key)
    return false unless value
    value[:payload] = args[:payload]

    key_ttl = args[:ttl] || @redis.ttl(key)

    @redis.multi do |multi|
      multi.set(key, serializer.pack(value), ex: key_ttl)
      multi.expire(token_to_owner(hash_get(value, :owner), token), key_ttl)
    end

    true
  end

  # Iterate all exist tokens of an owner
  #
  # @param [String] owner
  #
  # @return [Enumerator]
  def owned_by(owner)
    owned_tokens(owner).map { |token| [token, redis_get(token_to_key(token))] }
  end

  # Delete a token
  #
  # @param [String] token
  #
  # @return [Boolean]
  def del(token)
    key = token_to_key(token)
    value = redis_get(key)
    return false unless value

    @redis.multi do |multi|
      multi.del(key)
      multi.del(token_to_owner(hash_get(value, :owner), token))
    end

    true
  end

  alias delete del

  # Delete all tokens of an owner
  #
  # @params [String] owner
  #
  # @return [Integer] number of deleted tokens
  def del_all(owner)
    deleted = 0
    owned_tokens(owner).each do |token|
      del(token)
      deleted += 1
    end

    deleted
  end

  alias delete_all del_all

  # Retrieve the remaining ttl of a token
  #
  # @return [Integer] ttl
  def ttl(token)
    @redis.ttl(token_to_key(token))
  end

  # Use custom serialization class
  #
  # Base serializer example:
  #   class RedisToken
  #     class Serializers
  #       class Native
  #         def pack(value)
  #           Marshal.dump(value)
  #         end
  #
  #         def unpack(value)
  #           Marshal.load(value)
  #         end
  #       end
  #     end
  #   end
  #
  # MessagePack example:
  #   require 'msgpack'
  #
  #   class MsgPackSerializer
  #     def pack(value)
  #       MessagePack.pack(value)
  #     end
  #
  #     def unpack(value)
  #       MessagePack.unpack(value)
  #     end
  #   end
  #
  #   RedisToken.new(prefix: PREFIX).use(MsgPackSerializer)
  #
  # @param [Object] serializer_class
  #
  # @return [RedisToken]
  def use(serializer_class)
    @serializer_class = serializer_class
    self
  end

  private

  def generate_token
    SecureRandom.hex(16)
  end

  def init_params(args)
    @default_ttl = args[:ttl] || DEFAULT_TTL
    @prefix = args[:prefix] || DEFAULT_PREFIX

    @serializer_class = args[:serializer_class]
    @serializer_class = Serializers::Native unless @serializer_class
  end

  def token_to_key(token)
    "#{@prefix}#{token}"
  end

  def token_to_owner(owner, token)
    "#{@prefix}#{owner}.#{token}"
  end

  def owner_key_to_token(owner, key)
    key.sub("#{@prefix}#{owner}.", '')
  end

  def redis_get(key)
    value = @redis.get(key)
    return unless value
    serializer.unpack(value)
  end

  def owned_tokens(owner)
    mask = "#{@prefix}#{owner}.*"

    Enumerator.new do |y|
      cursor = '0'
      loop do
        cursor, r = @redis.scan(cursor, match: mask)

        r.each do |key|
          token = owner_key_to_token(owner, key)
          y << token
        end

        break if cursor == '0'
      end
    end
  end

  def serializer
    @serializer ||= @serializer_class.new
  end

  # Some serializers can't store symbols out of the box
  def hash_get(hash, sym)
    hash.key?(sym) ? hash[sym] : hash[sym.to_s]
  end
end
