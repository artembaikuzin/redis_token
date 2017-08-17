# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis_token/version'

Gem::Specification.new do |spec|
  spec.name          = 'redis_token'
  spec.version       = RedisToken::VERSION
  spec.authors       = ['Artem Baikuzin']
  spec.email         = ['ybinzu@gmail.com']

  spec.summary       = %q{API tokens redis store}
  spec.description   = %q{.}
  spec.homepage      = 'https://github.com/ybinzu/redis_token'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|bin)/})
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'redis', '~> 3.3', '>= 3.3.3'

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.10', '>= 5.10.3'
  spec.add_development_dependency 'minitest-reporters', '~> 1.1', '>= 1.1.14'
end
