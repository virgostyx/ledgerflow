class Peppol::Actions::SendToDigiteal
  extend LightService::Action

  expects :invoice, :ubl_xml
  promises :peppol_id

  executed do |ctx|
    conn = Faraday.new(url: DIGITEAL_API_URL) do |f|
      f.request :retry, max: 2, interval: 0.5
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/api/invoices") do |req|
      req.headers["Authorization"] = "Bearer #{DIGITEAL_API_KEY}"
      req.headers["Content-Type"]  = "application/xml"
      req.body = ctx.ubl_xml
    end

    body = JSON.parse(response.body)
    ctx.peppol_id = body["id"]
  rescue Faraday::Error => e
    ctx.fail!("Digiteal API error: #{e.message}")
  rescue JSON::ParserError => e
    ctx.fail!("Invalid Digiteal response: #{e.message}")
  end
end
