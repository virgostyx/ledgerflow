require "zlib"

# A reader of ZIP archives, with the standard library only (Zlib): the central directory, entries stored or deflated. It reads; it never extracts to a path (a name that
# climbs out of the archive is refused, nothing is written to disk), so that a package from outside is safe to open.
module LedgerVerify
  module ZipReader
    class Error < StandardError; end

    EOCD = [ 0x06054b50 ].pack("V").freeze
    CENTRAL = 0x02014b50
    LOCAL = 0x04034b50
    MAX_ENTRY = 2 * 1024 * 1024 * 1024 # a package entry beyond this is not a package

    # => { "name" => bytes }
    def self.read(data)
      data = data.b
      eocd = data.rindex(EOCD) or raise Error, "not a ZIP archive (no end of central directory)"
      count, _size, offset = data[eocd + 10, 12].unpack("vVV")
      files = {}
      count.times do
        raise Error, "the central directory is damaged" unless data[offset, 4]&.unpack1("V") == CENTRAL

        _version, _needed, flags, method, _time, _date, _crc, csize, usize, nlen, elen, clen, _disk, _int, _ext, local = data[offset + 4, 42].unpack("vvvvvvVVVvvvvvVV")
        name = data[offset + 46, nlen].force_encoding(Encoding::UTF_8)
        usize, csize, local = zip64(data[offset + 46 + nlen, elen], usize, csize, local)
        offset += 46 + nlen + elen + clen
        raise Error, "unsafe name in the archive: #{name.inspect}" if name.start_with?("/") || name.split("/").include?("..") || name.include?("\0")
        raise Error, "encrypted entry: #{name}" if flags & 1 == 1
        raise Error, "entry too large: #{name}" if usize > MAX_ENTRY
        next if name.end_with?("/")

        files[name] = content(data, local, method, csize, usize, name)
      end
      files
    end

    # ZIP64: a size or an offset that does not fit in 32 bits (or that the writer did not know when it began) is 0xFFFFFFFF, and the real one is in the extra field 0x0001.
    def self.zip64(extra, usize, csize, local)
      values = nil
      position = 0
      while position + 4 <= extra.bytesize
        id, size = extra[position, 4].unpack("vv")
        values = extra[position + 4, size].unpack("Q<*") if id == 1
        position += 4 + size
      end
      return [ usize, csize, local ] unless values

      take = -> { values.shift }
      usize = take.call if usize == 0xFFFFFFFF
      csize = take.call if csize == 0xFFFFFFFF
      local = take.call if local == 0xFFFFFFFF
      [ usize, csize, local ]
    end
    private_class_method :zip64

    def self.content(data, local, method, csize, usize, name)
      raise Error, "the local header of #{name} is damaged" unless data[local, 4]&.unpack1("V") == LOCAL

      nlen, elen = data[local + 26, 4].unpack("vv")
      raw = data[local + 30 + nlen + elen, csize]
      bytes = case method
      when 0 then raw
      when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
      else raise Error, "compression method #{method} of #{name} is not supported"
      end
      raise Error, "#{name} is not the size the archive says" unless bytes.bytesize == usize

      bytes.force_encoding(Encoding::UTF_8)
    rescue Zlib::Error => e
      raise Error, "#{name} cannot be read: #{e.message}"
    end
    private_class_method :content
  end
end
