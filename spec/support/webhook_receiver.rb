# F13c: the receiver of the specs. It does what the documentation tells a receiver to do: recompute the signature from the raw body with its secret
# and answer 400 when it differs, 200 otherwise. `fail_with` makes it answer that status instead, to test the retries.
class WebhookReceiver
  attr_reader :deliveries, :rejected
  attr_accessor :secret, :fail_with

  def initialize(secret) = (@secret, @deliveries, @rejected = secret, [], [])

  def call(request)
    return { status: fail_with, body: "down" } if fail_with

    signature = request.headers["X-Ledgerflow-Signature"]
    if Webhooks::Signature.verify(secret, signature, request.body)
      @deliveries << { body: JSON.parse(request.body), headers: request.headers }
      { status: 200, body: "ok" }
    else
      @rejected << { body: request.body, signature: signature }
      { status: 400, body: "bad signature" }
    end
  end
end

module WebhookHelpers
  PUBLIC_IP = "93.184.216.34".freeze

  # The receiver sits at a public name (resolved to a public address): the guard of the application is the real one.
  def receiver_at(url, secret)
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with(URI(url).host).and_return([ PUBLIC_IP ])
    WebhookReceiver.new(secret).tap { |receiver| stub_request(:post, url).to_return { |request| receiver.call(request) } }
  end

  def subscribe(url: "https://hooks.example.com/ledgerflow", events: WebhookSubscription::EVENTS, **attrs)
    WebhookSubscription.create!(name: "Test", url: url, events: events, secret: WebhookSubscription.generate_secret, **attrs)
  end
end

RSpec.configure { |config| config.include WebhookHelpers }
