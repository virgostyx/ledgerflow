require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  let(:base_classes) { "flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors" }

  describe '#nav_class' do
    def with_path(path, &)
      allow(helper).to receive(:request).and_return(double('request', path: path))
      yield
    end

    it 'returns active classes on an exact path match' do
      with_path('/accounting') do
        result = helper.nav_class('/accounting')
        expect(result).to include('bg-primary-100', 'text-primary-700')
      end
    end

    it 'returns active classes on a sub-path (prefix) match' do
      with_path('/accounting/reports/trial_balance') do
        result = helper.nav_class('/accounting/reports')
        expect(result).to include('bg-primary-100', 'text-primary-700')
      end
    end

    it 'returns inactive classes when path does not match' do
      with_path('/accounting/reports') do
        result = helper.nav_class('/accounting/journal_entries')
        expect(result).to include('text-gray-600', 'hover:bg-primary-50', 'hover:text-primary-700')
        expect(result).not_to include('bg-primary-100')
      end
    end

    it 'returns active classes when any of multiple paths matches' do
      with_path('/accounting/dashboard') do
        result = helper.nav_class('/accounting/reports', '/accounting/dashboard')
        expect(result).to include('bg-primary-100', 'text-primary-700')
      end
    end

    it 'includes the base classes in both active and inactive states' do
      with_path('/other') do
        expect(helper.nav_class('/accounting')).to include(base_classes)
      end
    end
  end

  describe '#user_initials' do
    it 'returns "?" for a blank string' do
      expect(helper.user_initials('')).to eq('?')
    end

    it 'returns "?" for nil' do
      expect(helper.user_initials(nil)).to eq('?')
    end

    it 'returns the first letter uppercased for a single-word name' do
      expect(helper.user_initials('alice')).to eq('A')
    end

    it 'returns two initials for a full name' do
      expect(helper.user_initials('Alice Martin')).to eq('AM')
    end

    it 'returns only two initials even for names with more words' do
      expect(helper.user_initials('Alice Marie Martin')).to eq('AM')
    end
  end
end
