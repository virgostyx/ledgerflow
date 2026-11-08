require "rails_helper"

# Sign-up page: the visitor can see what they type and how far they are from the 12-character minimum.
RSpec.describe "Sign-up password field", type: :system, js: true do
  before do
    visit new_user_registration_path
    page.execute_script("localStorage.setItem('lf_cookie_consent', 'refused')")
    visit new_user_registration_path
  end

  def password_field = find_field("user_password")

  it "counts characters towards the minimum, then confirms it is reached" do
    expect(page).to have_text("Minimum 12 characters")
    password_field.set("abc")
    expect(page).to have_text("3 of 12 characters")
    password_field.set("abcdefghijkl")
    expect(page).to have_text("✓ 12 characters or more")
  end

  it "shows and hides the password on request" do
    password_field.set("secret")
    expect(password_field[:type]).to eq("password")
    click_button "Show"
    expect(password_field[:type]).to eq("text")
    click_button "Hide"
    expect(password_field[:type]).to eq("password")
  end
end
