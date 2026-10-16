# B02b: why a request on an upload is refused; `status` is the HTTP status the page answers, `detail` what the person's device needs to go on (the chunks missing).
class Portal::UploadRefused < StandardError
  attr_reader :status, :detail

  def initialize(message, status:, **detail)
    super(message)
    @status = status
    @detail = detail
  end
end
