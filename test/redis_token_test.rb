require_relative '../lib/redis_token'

require 'test_helper'

require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class RedisTokenTest < MiniTest::Test
  def teardown
    redis_cleanup(RedisToken::DEFAULT_PREFIX)
  end

  def test_initialize
    r = RedisToken.new
    assert(r.redis.is_a?(Redis))
    assert_equal(RedisToken::DEFAULT_TTL, r.default_ttl)

    r = RedisToken.new(host: 'localhost', port: 12345, ttl: 9999)
    assert(r.redis.is_a?(Redis))
    assert_equal(9999, r.default_ttl)

    r = RedisToken.new(ttl: 8888)
    assert(r.redis.is_a?(Redis))
    assert_equal(8888, r.default_ttl)

    redis_instance = Redis.new
    r = RedisToken.new(redis_instance)
    assert_equal(redis_instance, r.redis)
    assert_equal(RedisToken::DEFAULT_TTL, r.default_ttl)

    r = RedisToken.new(redis_instance, ttl: 5555)
    assert_equal(redis_instance, r.redis)
    assert_equal(5555, r.default_ttl)
  end

  def test_create
    r = RedisToken.new
    token = SecureRandom.hex(16)
    payload = { type: :native }

    actual_token = r.create(token: token, payload: payload)

    assert_equal(token, actual_token)
    assert_equal(payload, r.created_value[:payload])
  end

  def test_get
    r = RedisToken.new
    owner = rand(999)
    actual_token = r.create(owner: owner)

    assert_equal(r.ttl(actual_token), RedisToken::DEFAULT_TTL)
    result = r.get(actual_token, ttl: 5000)

    assert_equal(5000, r.ttl(actual_token))
    assert_equal(owner, result[:owner])
    assert_nil(r.get('zero'))

    ttl_before = r.ttl(actual_token)
    result = r.get(actual_token, slide_expire: false, ttl: 10)

    assert_equal(owner, result[:owner])
    assert_equal(ttl_before, r.ttl(actual_token))
  end

  def test_del
    r = RedisToken.new
    actual_token = r.create(owner: rand(999))

    refute_nil(r.get(actual_token))
    assert(r.del(actual_token))
    assert_nil(r.get(actual_token))
    refute(r.del('zero'))
  end

  def test_owned_by
    r = RedisToken.new
    owner = rand(999)

    owned_tokens = []
    10.times { owned_tokens << r.create(owner: owner) }

    actual_tokens = []
    r.owned_by(owner).each { |token, _| actual_tokens << token }

    assert_equal(owned_tokens.sort, actual_tokens.sort)

    actual_tokens = []
    r.owned_by('another owner').each { |token, _| actual_tokens << token }

    assert(actual_tokens.empty?)

    no_owner = []
    3.times { no_owner << r.create }

    assert_equal(no_owner.sort, r.without_owner.map { |t, _| t }.sort)
    assert_equal((no_owner + owned_tokens).sort, r.all.map { |t, _| t }.sort)
  end

  def test_delete
    r = RedisToken.new
    owner = rand(999)

    tokens = []
    10.times { tokens << r.create(owner: owner) }

    assert_equal(10, r.owned_by(owner).count)
    assert_equal(10, r.delete_owned_by(owner))
    assert_equal(0, r.owned_by(owner).count)

    tokens.each { |t| assert_nil(r.get(t)) }

    no_owner = []
    5.times { no_owner << r.create }
    assert_equal(5, r.delete_without_owner)
    assert_equal(0, r.without_owner.count)

    no_owner.each { |t| assert_nil(r.get(t)) }

    assert_equal(0, r.delete_all)

    3.times { r.create(owner: rand(999)) }
    4.times { r.create }

    assert_equal(7, r.all.count)
    assert_equal(7, r.delete_all)
    assert_equal(0, r.all.count)

    assert_equal(0, r.delete_owned_by('nothing'))
  end

  def test_set
    r = RedisToken.new
    token = r.create(owner: rand(999), payload: { source: :native })

    new_payload = { source: :web }
    ttl_before = r.ttl(token)
    r.set(token, payload: new_payload)

    assert_equal(ttl_before, r.ttl(token))
    assert_equal(new_payload, r.get(token)[:payload])

    r.set(token, payload: nil, ttl: 99)
    assert_equal(99, r.ttl(token))
    assert_nil(r.get(token)[:payload])

    refute(r.set('zero', payload: '1234'))
  end
end
