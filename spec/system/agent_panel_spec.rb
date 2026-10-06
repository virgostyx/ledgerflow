require "rails_helper"

# A01: the journey of the panel in a real browser — open it by the tab and by the keyboard, ask a question, stop, give an opinion on an answer.
RSpec.describe "The agent's panel", type: :system, js: true do
  include_context "with_open_fiscal_year"

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    entity.update!(features: entity.features.merge("agent" => true))
    Agent::Setting.for_current_entity.update!(enabled: true)
    accept_agent_consent!
    login_as accountant, scope: :user
    visit accounting_root_path
  end

  it "opens by its tab, closes with Escape, and gives the focus back to the tab" do
    expect(page).to have_css("#agent_drawer", visible: :hidden)

    click_button "Assistant"
    expect(page).to have_css("#agent_drawer", visible: :visible)
    expect(page).to have_button("Close the assistant")

    page.send_keys(:escape)
    expect(page).to have_css("#agent_drawer", visible: :hidden)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-controls')")).to eq("agent_drawer")
  end

  it "opens with Ctrl+/" do
    page.send_keys([ :control, "/" ])

    expect(page).to have_css("#agent_drawer", visible: :visible)
  end

  it "starts a conversation, shows the question at once with a live bubble and a Stop button, and the Stop is recorded" do
    click_button "Assistant"
    click_button "New conversation"
    expect(page).to have_content("What the agent knows")

    fill_in "Your question", with: "Who owes me the most?"
    click_button "Send"

    expect(page).to have_css("#agent_drawer", text: "Who owes me the most?")
    expect(page).to have_content("Writing…")
    expect(find_field("Your question").value).to eq("")

    click_button "Stop"
    Timeout.timeout(5) { sleep 0.05 until Agent::Conversation.last.reload.stop_requested_at } # the request is made by the browser: wait for it
    expect(Agent::Conversation.last.stop_requested_at).to be_present
  end

  it "records an opinion on an answer" do
    conversation = Agent::Conversation.create!(user: accountant, title: "Earlier")
    answer = conversation.messages.create!(role: "assistant", content: "The balance is **12,00 EUR**.")
    visit accounting_root_path

    click_button "Assistant"
    click_link "Earlier"
    expect(page).to have_css("strong", text: "12,00 EUR")
    click_button "Useful"

    expect(page).to have_content("Thank you for your opinion.")
    expect(Agent::Feedback.find_by(message: answer)).to have_attributes(rating: "useful", user: accountant)
  end
end
