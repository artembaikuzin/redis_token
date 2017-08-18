# redis_token

API tokens redis store

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis_token'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis_token

## Usage

```ruby

before_action :create_service

def auth
  client = Client.find_by_email(params[:email])

  if client.password == params[:password]
    token = @redis_token.create(client.id, payload: { source: :native })
    json(access_token: token)

    ...
  end

  ...
end

def secured_method
  value = @redis_token.get(params[:access_token])
  return unathorized unless value

  client = Client.find_by_id(value[:owner])
  payload = value[:payload]

  ...
end

def client_tokens
  @tokens = []

  @redis_token.each(client.id) do |token, value|
    @tokens << { token: token, value: value }
  end
end

private

def create_service
  @redis_token ||= RedisToken.new(prefix: 'myproject.tokens.', ttl: 30.days)
end
```
