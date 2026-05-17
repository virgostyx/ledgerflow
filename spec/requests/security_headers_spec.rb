require "rails_helper"

RSpec.describe "Security headers", type: :request do
  let(:user) { create(:user, role: :accountant) }

  before { sign_in user }

  describe "Content-Security-Policy" do
    it "is present on authenticated pages" do
      get accounting_root_path
      expect(response.headers["Content-Security-Policy"]).to be_present
    end

    it "restricts object-src to none" do
      get accounting_root_path
      expect(response.headers["Content-Security-Policy"]).to include("object-src 'none'")
    end

    it "restricts default-src to self" do
      get accounting_root_path
      expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'")
    end

    it "allows wss for Action Cable" do
      get accounting_root_path
      expect(response.headers["Content-Security-Policy"]).to include("wss:")
    end
  end

  describe "X-Frame-Options" do
    it "is present" do
      get accounting_root_path
      expect(response.headers["X-Frame-Options"]).to be_present
    end
  end

  describe "X-Content-Type-Options" do
    it "is nosniff" do
      get accounting_root_path
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end
  end
end
