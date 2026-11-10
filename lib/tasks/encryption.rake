# Moving existing rows into (or out of) encryption. Each task accepts
# USER_ID=<id> to work on one account, and PAUSE=<seconds> to rest between
# batches. See Encryption::Backfill.
namespace :encryption do
  backfill = lambda do
    Encryption::Backfill.new(user_id: ENV["USER_ID"].presence&.to_i, pause: ENV.fetch("PAUSE", 0).to_f)
  end

  desc "Count rows that still hold plaintext in an encrypted column"
  task status: :environment do
    results = backfill.call.status
    results.each { |model, result| puts "#{model}: #{result.remaining} of #{result.checked} rows hold plaintext" }
    puts results.values.sum(&:remaining).zero? ? "Nothing left to encrypt." : "Plaintext remains."
  end

  desc "Check every value survives encryption, in memory, without writing anything"
  task rehearse: :environment do
    EncryptionCheck.verify!
    backfill.call.rehearse
    puts "Every value survived. Nothing was written."
  end

  desc "Encrypt rows written before encryption was on (verifies each row; safe to re-run)"
  task backfill: :environment do
    backfill.call.encrypt.each { |model, result| puts "#{model}: encrypted #{result.changed} of #{result.checked} rows" }
  end

  desc "Return encrypted rows to plaintext (the way back; needs CONFIRM=decrypt)"
  task decrypt: :environment do
    abort "Run with CONFIRM=decrypt to return rows to plaintext." unless ENV["CONFIRM"] == "decrypt"

    backfill.call.decrypt.each { |model, result| puts "#{model}: decrypted #{result.changed} of #{result.checked} rows" }
  end
end
