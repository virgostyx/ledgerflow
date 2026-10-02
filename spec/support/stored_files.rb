# Reaches the stored bytes of a document the way an intruder, a bad restore or a full disk would: behind the application.
module StoredFiles
  def stored_path(document) = ActiveStorage::Blob.service.path_for(document.file.blob.key)

  def tamper_with_stored_file(document)
    bytes = File.binread(stored_path(document))
    File.binwrite(stored_path(document), bytes.dup.tap { |copy| copy.setbyte(copy.bytesize / 2, copy.getbyte(copy.bytesize / 2) ^ 0x01) }) # one bit
  end

  def delete_stored_file(document) = File.delete(stored_path(document))

  def restore_stored_file(document, bytes) = File.binwrite(stored_path(document), bytes)
end

RSpec.configure { |config| config.include StoredFiles }
