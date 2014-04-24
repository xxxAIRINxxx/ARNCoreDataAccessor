Pod::Spec.new do |s|
  s.name         = "ARNCoreDataAccessor"
  s.version      = "0.1.0"
  s.summary      = "Compact CoreData Access Class."
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.homepage     = "https://github.com/xxxAIRINxxx/ARNCoreDataAccessor"
  s.author       = { "Airin" => "xl1138@gmail.com" }
  s.source       = { :git => "https://github.com/xxxAIRINxxx/ARNCoreDataAccessor.git", :tag => "#{s.version}" }
  s.platform     = :ios, '5.0'
  s.requires_arc = true
  s.source_files = 'ARNCoreDataAccessor/*.{h,m}'
end
