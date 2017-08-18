require_relative '../lib/redis_token'

require 'test_helper'

require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class RedisTokenTest < MiniTest::Test
  def teardown
    redis_cleanup(PREFIX)
  end

  def test_initialize
    r = RedisToken.new
    assert_equal(r.redis.is_a?(Redis), true)
    assert_equal(r.default_ttl, RedisToken::DEFAULT_TTL)

    r = RedisToken.new(host: 'localhost', port: 12345, ttl: 9999)
    assert_equal(r.redis.is_a?(Redis), true)
    assert_equal(r.default_ttl, 9999)

    r = RedisToken.new(ttl: 8888)
    assert_equal(r.redis.is_a?(Redis), true)
    assert_equal(r.default_ttl, 8888)

    redis_instance = Redis.new
    r = RedisToken.new(redis_instance)
    assert_equal(r.redis, redis_instance)
    assert_equal(r.default_ttl, RedisToken::DEFAULT_TTL)

    r = RedisToken.new(redis_instance, ttl: 5555)
    assert_equal(r.redis, redis_instance)
    assert_equal(r.default_ttl, 5555)
  end

  def test_create
    r = redis_token_instance
    token = SecureRandom.hex(16)
    payload = { type: :native }

    client_id = rand(9999)
    actual_token = r.create(client_id, token: token, payload: payload)

    assert_equal(token, actual_token)
    assert_equal(payload, r.created_value[:payload])

    assert_raises RuntimeError do
      r.create(nil)
    end
  end

  def test_get
    r = redis_token_instance
    owner = rand(999)
    actual_token = r.create(owner)

    assert_equal(r.ttl(actual_token), RedisToken::DEFAULT_TTL)
    result = r.get(actual_token, ttl: 5000)
    assert_equal(r.ttl(actual_token), 5000)
    assert_equal(result[:owner], owner)
    assert_nil(r.get('zero'))

    ttl_before = r.ttl(actual_token)
    result = r.get(actual_token, slide_expire: false, ttl: 10)
    assert_equal(result[:owner], owner)
    assert_equal(ttl_before, r.ttl(actual_token))
  end

  def test_del
    r = redis_token_instance
    actual_token = r.create(rand(999))
    refute_nil(r.get(actual_token))
    assert(r.del(actual_token))
    assert_nil(r.get(actual_token))
    refute(r.del('zero'))
  end

  def test_owned_by
    r = redis_token_instance
    owner = rand(999)

    expected_tokens = []
    10.times do
      expected_tokens << r.create(owner)
    end

    actual_tokens = []
    r.owned_by(owner).each do |token, _|
      actual_tokens << token
    end

    assert_equal(expected_tokens.sort, actual_tokens.sort)

    actual_tokens = []
    r.owned_by('no owner').each do |token, _|
      actual_tokens << token
    end

    assert(actual_tokens.empty?)

    result = r.owned_by(owner).take(2)
    assert_equal(result.size, 2)
  end

  def test_delete_all
    r = redis_token_instance
    owner = rand(999)

    tokens = []
    10.times { tokens << r.create(owner) }

    before_delete = r.owned_by(owner).size
    assert_equal(r.delete_all(owner), 10)
    after_delete = r.owned_by(owner).size

    assert_equal(10, before_delete)
    assert_equal(0, after_delete)

    tokens.each { |t| assert_nil(r.get(t)) }
  end

  def test_set
    r = redis_token_instance
    token = r.create(rand(999), payload: { source: :native })

    new_payload = { source: :web }
    ttl_before = r.ttl(token)
    r.set(token, payload: new_payload)
    assert_equal(r.get(token)[:payload], new_payload)

    ttl_after = r.ttl(token)
    assert_equal(ttl_before, ttl_after)

    r.set(token, payload: nil, ttl: 99)
    assert_equal(r.ttl(token), 99)
    assert_nil(r.get(token)[:payload])

    refute(r.set('zero', payload: '1234'))
  end

  private

  PREFIX = 'tokens.'

  def redis_token_instance
    RedisToken.new(prefix: PREFIX)
  end
end
