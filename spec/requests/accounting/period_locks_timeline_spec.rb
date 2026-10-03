require "rails_helper"

# F01 (spec §4, interface): a monthly timeline with a padlock per month, per VAT period and per fiscal year,
# and a grouped lock action.
RSpec.describe "Periods timeline", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) } # the global role no longer matters
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  let(:year_start) { fiscal_year.start_date }
  let(:first_month) { year_start.beginning_of_month }

  before { sign_in accountant }

  def cell(kind, month)
    css = "[data-timeline='#{kind}'] [data-month='#{month.strftime('%Y-%m')}']"
    Nokogiri::HTML(response.body).at_css(css)&.[]("data-state")
  end

  describe "GET /accounting/period_locks" do
    it "shows a month of the year as locked, open or partly locked, per kind" do
      create(:period_lock, kind: :accounting, starts_on: first_month, ends_on: first_month.end_of_month)
      create(:period_lock, kind: :accounting, starts_on: first_month.next_month, ends_on: first_month.next_month + 9)
      create(:period_lock, kind: :vat, starts_on: first_month, ends_on: first_month.end_of_month)

      get accounting_period_locks_path

      expect(cell("accounting", first_month)).to eq("locked")
      expect(cell("accounting", first_month.next_month)).to eq("partial")
      expect(cell("accounting", first_month.next_month.next_month)).to eq("open")
      expect(cell("vat", first_month)).to eq("locked")
      expect(cell("vat", first_month.next_month)).to eq("open")
    end

    it "does not count a period that was unlocked" do
      create(:period_lock, starts_on: first_month, ends_on: first_month.end_of_month, status: :unlocked, unlocked_by: accountant, unlocked_at: Time.current, unlock_reason: "x")

      get accounting_period_locks_path

      expect(cell("accounting", first_month)).to eq("open")
    end

    it "shows the fiscal year as locked when a fiscal-year lock covers it" do
      create(:period_lock, kind: :fiscal_year, starts_on: fiscal_year.start_date, ends_on: fiscal_year.end_date)

      get accounting_period_locks_path

      expect(Nokogiri::HTML(response.body).at_css("[data-timeline='fiscal_year'] [data-state]")["data-state"]).to eq("locked")
    end

    it "shows the months of the year asked for" do
      get accounting_period_locks_path, params: { fiscal_year_id: fiscal_year.id }

      expect(response).to have_http_status(:ok)
      expect(cell("accounting", first_month)).to eq("open")
    end
  end

  describe "POST /accounting/period_locks/lock_months" do
    let(:months) { [ first_month, first_month.next_month ].map { |m| m.strftime("%Y-%m") } }

    it "locks every month ticked, one lock and one audit entry each" do
      expect { post lock_months_accounting_period_locks_path, params: { months: months, kind: "accounting", reason: "Q1 reviewed" } }
        .to change(Accounting::PeriodLock, :count).by(2)

      expect(Accounting::PeriodLock.order(:starts_on).map { |l| [ l.starts_on, l.ends_on ] })
        .to eq([ [ first_month, first_month.end_of_month ], [ first_month.next_month, first_month.next_month.end_of_month ] ])
      expect(Accounting::AuditLog.where(action: "lock_period").count).to eq(2)
      expect(response).to redirect_to(accounting_period_locks_path(fiscal_year_id: fiscal_year.id))
    end

    it "skips a month that is already locked, and tells how many it locked" do
      create(:period_lock, starts_on: first_month, ends_on: first_month.end_of_month)

      expect { post lock_months_accounting_period_locks_path, params: { months: months, kind: "accounting" } }.to change(Accounting::PeriodLock, :count).by(1)
      expect(flash[:notice]).to match(/1 month/)
    end

    it "refuses a month that is not a month, and locks nothing" do
      expect { post lock_months_accounting_period_locks_path, params: { months: [ "2026-13", "nonsense" ], kind: "accounting" } }.not_to change(Accounting::PeriodLock, :count)

      expect(flash[:alert]).to be_present
    end

    it "refuses to lock without any month ticked" do
      expect { post lock_months_accounting_period_locks_path, params: { kind: "accounting" } }.not_to change(Accounting::PeriodLock, :count)

      expect(flash[:alert]).to be_present
    end

    it "is refused to an assistant" do
      sign_out accountant
      sign_in assistant

      expect { post lock_months_accounting_period_locks_path, params: { months: months, kind: "accounting" } }.not_to change(Accounting::PeriodLock, :count)
    end
  end
end
