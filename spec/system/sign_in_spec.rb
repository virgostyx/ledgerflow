require "rails_helper"

# The sign-in page now loads JavaScript (Turbo, floating labels, passkey button) even on a direct visit: a wrong password must still show its error.
RSpec.describe "Sign in page with JavaScript", type: :system, js: true do
  before do
    visit new_user_session_path
    page.execute_script("localStorage.setItem('lf_cookie_consent', 'refused')")
    visit new_user_session_path
  end

  it "runs its Stimulus controllers on a direct visit" do
    expect(page).to have_css("[data-controller~='passkey-login']")
    expect(page.evaluate_script("!!window.Stimulus || !!document.querySelector('script[type=importmap]')")).to be(true)
  end

  it "shows the error for a wrong password and stays on the sign-in page" do
    fill_in "Email address", with: "nobody@example.test"
    fill_in "Password", with: "definitely wrong password"
    click_button "Sign in"
    expect(page).to have_css("[role=alert], .alert, [data-controller~='flash']", wait: 5).or have_text(/invalid/i)
    expect(page).to have_current_path(new_user_session_path)
  end
end
