# Real pictures for the specs of the portal's uploads, made by ImageMagick.
module ExternalCommandForSpecs
  def self.run(width, height, format, extra)
    out, status = Open3.capture2('convert', '-size', "#{width}x#{height}", 'xc:skyblue', *extra, '-quality', '85', "#{format}:-")
    raise "convert failed" unless status.success?

    out.b
  end
end
