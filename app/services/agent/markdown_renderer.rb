# What the model wrote, as safe HTML (A01): raw HTML is dropped by the parser, then only the tags an answer needs are kept. No image (a URL is a way out for data)
# and no link: the links to the books are built by the application from checked references (A05), never from an address the model wrote.
module Agent::MarkdownRenderer
  TAGS = %w[p br strong em code pre ul ol li table thead tbody tr th td h3 h4 h5 blockquote].freeze

  def self.html(text)
    return "" if text.blank?

    rendered = Commonmarker.to_html(text.to_s, options: { extension: { table: true } })
    ActionController::Base.helpers.sanitize(rendered, tags: TAGS, attributes: [])
  end
end
