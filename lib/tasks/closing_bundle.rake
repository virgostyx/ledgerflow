namespace :closing_bundle do
  desc "Verify every file of a closing bundle against its manifest (FILE=path/to/bundle.zip)"
  task verify: :environment do
    file = ENV.fetch("FILE") { abort "Usage: rake closing_bundle:verify FILE=path/to/bundle.zip" }
    result = Accounting::ClosingBundle.verify(File.binread(file))
    if result.valid?
      puts "[closing_bundle] #{result.checked} files verified: OK"
    else
      puts "[closing_bundle] MISMATCH: #{result.mismatches.join(', ')} | MISSING: #{result.missing.join(', ')}"
      exit(1)
    end
  end
end
