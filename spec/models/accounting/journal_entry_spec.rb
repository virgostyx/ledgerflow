require 'rails_helper'

RSpec.describe Accounting::JournalEntry, type: :model do
  describe 'associations' do
    it { should belong_to(:journal).class_name('Accounting::Journal') }
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
    it { should have_many(:lines).class_name('Accounting::JournalEntryLine').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:journal_entry) }

    it { should validate_presence_of(:entry_date) }
    it { should validate_uniqueness_of(:reference).ignoring_case_sensitivity }

    context 'quand validée (non-brouillon)' do
      subject { build(:journal_entry, :posted) }
      it { should validate_presence_of(:reference) }
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(draft: 0, posted: 1, reversed: 2) }
  end

  describe 'statuts AASM (Statusable)' do
    let(:entry) { create(:journal_entry) }

    it 'démarre en draft' do
      expect(entry).to be_draft
    end

    it 'peut passer en posted via post!' do
      entry.post!
      expect(entry.reload).to be_posted
    end

    it 'peut passer en reversed depuis posted' do
      entry.post!
      entry.reload.reverse!
      expect(entry.reload).to be_reversed
    end
  end

  describe 'immuabilité (Immutable)' do
    let(:entry) { create(:journal_entry, :posted) }

    it_behaves_like 'an immutable posted record' do
      subject { entry }
    end
  end

  describe 'PaperTrail (Auditable)' do
    let(:entry) { create(:journal_entry) }

    it 'crée une version à la création' do
      expect(entry.versions.count).to eq(1)
    end

    it 'crée une version à la mise à jour' do
      expect { entry.update!(description: 'modifié') }
        .to change { entry.versions.count }.by(1)
    end
  end

  describe 'scopes' do
    include_context 'with_open_fiscal_year'
    let!(:draft_entry)  { create(:journal_entry, :draft,  fiscal_year: fiscal_year) }
    let!(:posted_entry) { create(:journal_entry, :posted, fiscal_year: fiscal_year) }

    it '.draft retourne les écritures brouillon' do
      expect(Accounting::JournalEntry.draft).to include(draft_entry)
      expect(Accounting::JournalEntry.draft).not_to include(posted_entry)
    end

    it '.posted retourne les écritures validées' do
      expect(Accounting::JournalEntry.posted).to include(posted_entry)
      expect(Accounting::JournalEntry.posted).not_to include(draft_entry)
    end
  end
end
