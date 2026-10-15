require "rails_helper"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify/merkle")

# B03c step 1: the Merkle tree of the anchors, the construction of RFC 6962 (leaf = SHA-256(0x00 || data), node = SHA-256(0x01 || left || right), an odd node goes up as it is).
# The reference vectors are the ones of the Certificate Transparency reference implementation (the roots of the trees of the first eight of its test leaves).
RSpec.describe LedgerVerify::Merkle do
  # the leaves of the reference implementation: the first is empty
  def data = [ "" ] + %w[00 10 2021 3031 40414243 5051525354555657 606162636465666768696a6b6c6d6e6f].map { |hex| [ hex ].pack("H*") }

  def hex(bytes) = bytes.unpack1("H*")

  it "gives the hash of an empty string for an empty tree" do
    expect(hex(described_class.root([]))).to eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  end

  {
    1 => "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d",
    2 => "fac54203e7cc696cf0dfcb42c92a1d9dbaf70ad9e621f4bd8d98662f00e3c125",
    3 => "aeb6bcfe274b70a14fb067a5e5578264db0fa9b51af5e0ba159158f329e06e77",
    4 => "d37ee418976dd95753c1c73862b9398fa2a2cf9b4ff0fdfe8b30cd95209614b7",
    5 => "4e3bbb1f7b478dcfe71fb631631519a3bca12c9aefca1612bfce4c13a86264d4",
    6 => "76e67dadbcdf1e10e1b74ddc608abd2f98dfb16fbce75277b5232a127f2087ef",
    7 => "ddb89be403809e325750d3d263cd78929c2942b7942a34b77e122c9594a74c8c",
    8 => "5dc9da79a70659a9ad559cb701ded9a2ab9d823aad2f4960cfe370eff4604328"
  }.each do |count, root|
    it "gives the reference root of the first #{count} leaves" do
      expect(hex(described_class.root(data.first(count)))).to eq(root)
    end
  end

  # The recursive definition of the RFC: split at the largest power of two below n.
  def rfc_root(items)
    return Digest::SHA256.digest("") if items.empty?
    return described_class.leaf_hash(items.first) if items.one?

    k = 1
    k *= 2 while k * 2 < items.size
    described_class.node_hash(rfc_root(items.first(k)), rfc_root(items.drop(k)))
  end

  it "is the tree of the RFC for every size from 1 to 70 (an odd node goes up as it is)" do
    leaves = Array.new(70) { |i| Digest::SHA256.digest("entry-#{i}") }

    (1..70).each { |n| expect(described_class.root(leaves.first(n))).to eq(rfc_root(leaves.first(n))), "size #{n}" }
  end

  it "changes when one leaf changes, when two are swapped, when one is added or taken away" do
    leaves = Array.new(9) { |i| Digest::SHA256.digest("e#{i}") }
    root = described_class.root(leaves)

    expect(described_class.root(leaves.dup.tap { |l| l[4] = Digest::SHA256.digest("other") })).not_to eq(root)
    expect(described_class.root(leaves.dup.tap { |l| l[2], l[3] = l[3], l[2] })).not_to eq(root)
    expect(described_class.root(leaves + [ Digest::SHA256.digest("more") ])).not_to eq(root)
    expect(described_class.root(leaves.first(8))).not_to eq(root)
  end

  it "tells a leaf from a node: a tree of two leaves is not the leaf of their concatenation" do
    a = Digest::SHA256.digest("a")
    b = Digest::SHA256.digest("b")

    expect(described_class.root([ a, b ])).not_to eq(described_class.root([ a + b ]))
  end

  it "takes the hash of an entry as its hexadecimal text too" do
    entry = Digest::SHA256.hexdigest("an entry")

    expect(described_class.root_of_hex([ entry ])).to eq(described_class.root([ [ entry ].pack("H*") ]).unpack1("H*"))
  end
end
