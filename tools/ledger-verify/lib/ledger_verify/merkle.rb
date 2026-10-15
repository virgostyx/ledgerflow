require "digest"

# The Merkle tree of the anchors, as RFC 6962: a leaf is SHA-256(0x00 || data), a node is SHA-256(0x01 || left || right), and a node left without a sibling goes up as it is.
# The two prefixes keep a leaf from ever being taken for a node. Standard library only (see canonical.rb on why the application loads this very file).
module LedgerVerify
  module Merkle
    def self.leaf_hash(data) = Digest::SHA256.digest("\x00".b + data.b)

    def self.node_hash(left, right) = Digest::SHA256.digest("\x01".b + left.b + right.b)

    # `leaves`: the data of the leaves (for an anchor, the 32 bytes of the hash of each entry), in order. The root, as 32 bytes.
    def self.root(leaves)
      return Digest::SHA256.digest("") if leaves.empty?

      level = leaves.map { |data| leaf_hash(data) }
      level = level.each_slice(2).map { |pair| pair.one? ? pair.first : node_hash(*pair) } while level.size > 1
      level.first
    end

    # The same, for hashes written in hexadecimal; the root in hexadecimal.
    def self.root_of_hex(hashes) = root(hashes.map { |hash| [ hash ].pack("H*") }).unpack1("H*")
  end
end
