namespace :exports do
  desc "Write docs/exports.md from Exports::Dictionary"
  task docs: :environment do
    Rails.root.join("docs/exports.md").write(Exports::Dictionary.markdown)
  end
end
