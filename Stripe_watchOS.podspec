Pod::Spec.new do |s|
  s.name             = "Stripe_watchOS"
  s.version          = "0.1.0"
  s.summary          = "Stripe watchOS helper"

  s.description      = <<-DESC
                       Allows to converts PKPayment object to Stripe Token on watchOS.
                       DESC

  s.homepage         = "https://github.com/appintheair/stripe-watchos-tokenizer"
  s.license          = 'MIT'
  s.author           = { "Sergey Pronin" => "sergey.pronin@appintheair.mobi" }
  s.source           = { :git => "https://github.com/appintheair/stripe-watchos-tokenizer.git", :tag => s.version.to_s }

  s.platform     = :watchos, '3.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'

  s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'Foundation', 'WatchKit', 'PassKit'
end
