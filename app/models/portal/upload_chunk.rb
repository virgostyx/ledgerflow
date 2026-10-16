# B02b: one piece (1 MB) of an upload on its way. Kept until the firm's side has taken the file in.
class Portal::UploadChunk < ApplicationRecord
  belongs_to :upload, class_name: "Portal::Upload", inverse_of: :chunks
end
