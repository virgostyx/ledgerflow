require "net/http"

# F13c: sends one delivery: the body is the payload, signed with the secrets of the subscription, to the address that was checked. A 2xx is delivered; anything
# else (or no answer) is an attempt that failed and is tried again later, at growing intervals, up to MAX_ATTEMPTS, after which the delivery is given up
# (it can be sent again by hand). Failures in a row suspend the subscription, and its owners are told.
class Webhooks::Deliver
  BACKOFF = [ 1.minute, 5.minutes, 30.minutes, 2.hours, 6.hours, 12.hours, 24.hours ].freeze # then the last one again
  MAX_ATTEMPTS = 8
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # => the delivery
  def self.call(delivery)
    subscription = delivery.webhook_subscription
    return delivery unless delivery.status == "pending"
    return delivery.tap { |d| d.update!(status: "held") } if subscription.suspended? || !subscription.active?

    body = JSON.generate(delivery.payload)
    code, error = post(subscription, delivery, body)
    delivery.attempts += 1
    if code && code.between?(200, 299)
      delivery.update!(status: "delivered", delivered_at: Time.current, last_response_code: code, last_error: nil, next_attempt_at: nil)
      subscription.update_columns(consecutive_failures: 0, last_delivery_at: Time.current)
    else
      failed(delivery, subscription, code, error || "HTTP #{code}")
    end
    delivery
  end

  def self.post(subscription, delivery, body)
    uri, ip = Webhooks::UrlGuard.resolve!(subscription.url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout, http.read_timeout = OPEN_TIMEOUT, READ_TIMEOUT
    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json", "User-Agent" => "LedgerFlow-Webhooks/1",
                                  "X-LedgerFlow-Event" => delivery.event, "X-LedgerFlow-Delivery" => delivery.id.to_s, "X-LedgerFlow-Event-Id" => delivery.event_id,
                                  Webhooks::Signature::HEADER => Webhooks::Signature.header(subscription.signing_secrets, body))
    request.body = body
    [ http.request(request).code.to_i, nil ]
  rescue Webhooks::UrlGuard::Refused => e
    [ nil, "refused: #{e.message}" ]
  rescue StandardError => e # a timeout, a refused connection, a broken TLS: an attempt that failed, whatever the reason
    [ nil, "#{e.class.name.demodulize}: #{e.message}".first(255) ]
  end
  private_class_method :post

  def self.failed(delivery, subscription, code, error)
    gave_up = delivery.attempts >= MAX_ATTEMPTS
    delivery.update!(status: gave_up ? "failed" : "pending", last_response_code: code, last_error: error.to_s.first(255),
                     next_attempt_at: gave_up ? nil : BACKOFF.fetch(delivery.attempts - 1, BACKOFF.last).from_now)
    ActiveRecord.after_all_transactions_commit { Webhooks::DeliverJob.set(wait_until: delivery.next_attempt_at).perform_later(delivery.id) } unless gave_up

    subscription.increment!(:consecutive_failures)
    suspend(subscription) if subscription.consecutive_failures >= subscription.max_failures && !subscription.suspended?
  end
  private_class_method :failed

  def self.suspend(subscription)
    subscription.suspend!("#{subscription.consecutive_failures} failed attempts in a row")
    ActsAsTenant.with_tenant(subscription.entity) do
      UserEntity.current.where(role: :admin, entity: subscription.entity).includes(:user).find_each do |membership|
        Accounting::Notify.call(user: membership.user, event: "webhook_suspended:#{subscription.id}:#{Date.current}", subject: subscription,
                                data: { name: subscription.name, url: subscription.url, reason: subscription.suspended_reason })
      end
    end
  end
  private_class_method :suspend
end
