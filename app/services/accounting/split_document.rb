# Cuts a PDF into one document per range of pages (F03): a scan that holds several invoices becomes several documents,
# each linked to the parent. The parent is never modified. Ranges are "1-2, 3, 5": pages count from 1, each page may
# be in one range only, and the whole document in one range is not a split. A child is an ordinary upload (checked,
# deduplicated, audited, read); one that already exists is reported, not duplicated.
# Uses pdfseparate and pdfunite (poppler), without a shell.
class Accounting::SplitDocument
  MAX_RANGES = 50
  MAX_PAGES = 300

  def self.call(document:, ranges:, user:) = new(document, ranges, user).call

  def initialize(document, ranges, user)
    @document = document
    @ranges_text = ranges.to_s.strip
    @user = user
  end

  def call
    return refuse(:not_pdf) unless @document.content_type == "application/pdf" && !@document.extracted_data["unreadable"]
    return refuse(:archived) if @document.archived?

    bytes = @document.file.download
    pages = page_count(bytes)
    return refuse(:not_pdf) unless pages
    return refuse(:one_page) if pages < 2

    ranges = parse(pages)
    return refuse(:bad_ranges, pages: pages) unless ranges
    return refuse(:whole_document) if ranges == [ [ 1, pages ] ]

    children, refused = cut(bytes, ranges)
    return refuse(:nothing_created, refused: refused) if children.empty?

    audit(children)
    LightService::Context.make(children: children, refused: refused)
  rescue Accounting::ExternalCommand::Failed => e
    refuse(:tool_failed, detail: e.message)
  end

  private

  def page_count(bytes)
    PDF::Reader.new(StringIO.new(bytes)).page_count.then { |count| count.between?(1, MAX_PAGES) ? count : nil }
  rescue StandardError
    nil
  end

  # "1-2, 3" => [[1, 2], [3, 3]]; nil when it is not a clean list of distinct pages of this document
  def parse(pages)
    parts = @ranges_text.split(",").map(&:strip)
    return if parts.empty? || parts.size > MAX_RANGES

    ranges = parts.map do |part|
      match = part.match(/\A(\d+)(?:\s*-\s*(\d+))?\z/) or return nil
      first = match[1].to_i
      last = (match[2] || match[1]).to_i
      return nil unless first >= 1 && first <= last && last <= pages

      [ first, last ]
    end
    return if ranges.flat_map { |first, last| (first..last).to_a }.then { |all| all.uniq.size != all.size }

    ranges
  end

  # => [children created, messages for the ranges refused]
  def cut(bytes, ranges)
    children = []
    refused = []
    @cut_before = Accounting::Document.where(parent_id: @document.id).to_a # fresh from the database, not the cached association
    Dir.mktmpdir("split") do |dir|
      File.binwrite(File.join(dir, "in.pdf"), bytes)
      Accounting::ExternalCommand.run("pdfseparate", File.join(dir, "in.pdf"), File.join(dir, "page-%d.pdf"))
      ranges.each do |first, last|
        # pdfseparate/pdfunite do not give the same bytes twice, so the checksum cannot tell: the pages are remembered.
        if (existing = already_cut(first, last))
          refused << "#{child_name(first, last)}: #{I18n.t('documents.errors.duplicate', name: existing.name)}"
          next
        end
        result = Accounting::UploadDocument.call(io: StringIO.new(range_bytes(dir, first, last)), filename: child_name(first, last), user: @user,
                                                 origin: @document.origin, kind: @document.kind, parent: @document, details: { split: { first: first, last: last } })
        result.success? ? children << result[:document] : refused << "#{child_name(first, last)}: #{result.message}"
      end
    end
    [ children, refused ]
  end

  def already_cut(first, last)
    @cut_before.find { |child| child.extracted_data["split"] == { "first" => first, "last" => last } }
  end

  def range_bytes(dir, first, last)
    files = (first..last).map { |page| File.join(dir, "page-#{page}.pdf") }
    return File.binread(files.first) if files.one?

    Accounting::ExternalCommand.run("pdfunite", *files, File.join(dir, "range-#{first}-#{last}.pdf"))
    File.binread(File.join(dir, "range-#{first}-#{last}.pdf"))
  end

  # Named after the parent (never a path) and the pages.
  def child_name(first, last)
    base = File.basename(@document.name.to_s.tr("\\", "/"), ".*").presence || "document"
    "#{base} (#{first == last ? "page #{first}" : "pages #{first}-#{last}"}).pdf"
  end

  def audit(children)
    Accounting::AuditLog.record!(auditable: @document, action: "document_split", user: @user,
                                 payload: { ranges: @ranges_text, children: children.map(&:id) })
  end

  def refuse(reason, **extra)
    messages = extra.delete(:refused)
    LightService::Context.make(children: [], refused: messages || [], reason: reason).tap do |ctx|
      ctx.fail!(I18n.t("documents.errors.split_#{reason}", **extra.merge(count: MAX_RANGES)))
    end
  end
end
