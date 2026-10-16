# B02c: the dashboard as a document, made of the snapshots alone (the figures, their date, the provisional note, the word of the accountant once approved). Nothing is calculated here.
class Portal::DashboardPdf
  def self.call(snapshots, labels:)
    Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
      snapshots.each_with_index do |(company, snapshot), index|
        pdf.start_new_page if index.positive?
        pdf.text company.name, size: 18, style: :bold
        pdf.text labels.fetch("title"), size: 11
        pdf.text format(labels.fetch("updated"), date: snapshot.period_end.iso8601), size: 9
        pdf.text labels.fetch("provisional"), size: 9, style: :italic if snapshot.provisional
        pdf.move_down 10
        rows = Portal::Snapshot::INDICATORS.filter_map { |key| [ labels.fetch(key), snapshot.indicators[key].to_s ] if snapshot.indicators.key?(key) }
        rows = rows.map { |label, value| [ label, value.match?(/\A-?\d+\.\d{2}\z/) ? group(value) : value ] }
        pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 10 }) { column(1).align = :right }
        word = Portal::Snapshot.shown_word(snapshot)
        if word
          pdf.move_down 12
          pdf.text labels.fetch("word"), style: :bold
          pdf.text word, size: 10
        end
      end
    end.render
  end

  # 1500.00 -> 1,500.00 (the PDF is written in the language of the person only for its labels).
  def self.group(text)
    whole, fraction = text.split(".")
    sign = whole.start_with?("-") ? "-" : ""
    "#{sign}#{whole.delete('-').reverse.scan(/\d{1,3}/).join(',').reverse}.#{fraction}"
  end
  private_class_method :group
end
