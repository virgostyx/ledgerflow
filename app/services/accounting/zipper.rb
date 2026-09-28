# Builds a ZIP from [[path, content], ...] with a fixed entry time and sorted paths, so that the same files
# always give the same archive bytes.
class Accounting::Zipper
  FIXED_TIME = Zip::DOSTime.new(2000, 1, 1, 0, 0, 0)

  def self.build(files)
    Zip::OutputStream.write_buffer do |zip|
      files.sort_by(&:first).each do |path, content|
        zip.put_next_entry(Zip::Entry.new(nil, path, time: FIXED_TIME))
        zip.write(content)
      end
    end.string
  end

  # => { "path" => content } from ZIP data
  def self.read(data)
    zip = Zip::File.open_buffer(StringIO.new(data))
    zip.entries.to_h { |e| [ e.name, e.get_input_stream.read ] }
  end
end
