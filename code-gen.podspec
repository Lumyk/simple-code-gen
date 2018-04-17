
Pod::Spec.new do |s|
  s.name             = 'code-gen'
  s.version          = '0.0.2'
  s.summary          = 'code-gen.'
  s.description      = 'code-gen.'

  s.homepage         = 'https://github.com/lumyk/code-gen'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Evgeny Kalashnikov' => 'lumyfly@gmail.com' }
  s.source           = { :git => 'https://github.com/lumyk/code-gen.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'

  s.source_files = '*'

end
