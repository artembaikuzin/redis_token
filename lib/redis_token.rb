require 'redis_token/version'
require 'redis'

require 'securerandom'
require 'time'

class RedisToken
  # Token lives 14 days by default
  DEFAULT_TTL = 14 * 24 * 60 * 60

  attr_reader :redis
  attr_accessor :default_ttl
  attr_accessor :prefix
  attr_reader :created_value

  def initialize(args = {}, opts = {})
    @redis = if args.nil? || args.is_a?(Hash)
               init_params(args)
               Redis.new(args)
             else
               init_params(opts)
               args
             end

    @default_ttl ||= DEFAULT_TTL
  end

  def create(owner, args = {})
    raise 'owner should be specified' unless owner

    token = args[:token] || generate_token
    value = { owner: owner, at: Time.now }

    payload = args[:payload]
    value[:payload] = payload if payload

    @created_value = value
    key_ttl = args[:ttl] || @default_ttl

    @redis.multi do |multi|
      multi.set(token_to_key(token), Marshal.dump(value), ex: key_ttl)
      multi.set(token_to_owner(owner, token), nil, ex: key_ttl)
    end

    token
  end

  def get(token, args = {})
    key = token_to_key(token)
    value = redis_get(key)
    return unless value
    return value if args[:slide_expire] === false

    key_ttl = args[:ttl] || @default_ttl

    @redis.multi do |multi|
      multi.expire(key, key_ttl)
      multi.expire(token_to_owner(value[:owner], token), key_ttl)
    end

    value
  end

  def set(token, args = {})
    key = token_to_key(token)
    value = redis_get(key)
    return false unless value
    value[:payload] = args[:payload]

    key_ttl = args[:ttl] || @redis.ttl(key)

    @redis.multi do |multi|
      multi.set(key, Marshal.dump(value), ex: key_ttl)
      multi.expire(token_to_owner(value[:owner], token), key_ttl)
    end

    true
  end

  def each(owner)
    mask = "#{@prefix}#{owner}.*"

    cursor = 0
    loop do
      cursor, r = @redis.scan(cursor, match: mask)
      cursor = cursor.to_i

      r.each do |key|
        token = owner_key_to_token(owner, key)
        yield(token, redis_get(token_to_key(token)))
      end

      break if cursor == 0
    end
  end

  def del(token)
    key = token_to_key(token)
    value = redis_get(key)
    return false unless value

    @redis.multi do |multi|
      multi.del(key)
      multi.del(token_to_owner(value[:owner], token))
    end

    true
  end

  def ttl(token)
    @redis.ttl(token_to_key(token))
  end

  private

  def generate_token
    SecureRandom.hex(16)
  end

  def init_params(args)
    @default_ttl = args[:ttl]
    @prefix = args[:prefix]
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
    Marshal.load(value)
  end

  def check_owner(owner)
    raise 'owner should be specified' unless owner
  end
end
