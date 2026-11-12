namespace :content do
  desc "Import techniques, badges, tracks and shifts from content/ (CONTENT_DIR to override)"
  task import: :environment do
    root = ENV.fetch("CONTENT_DIR", Rails.root.join("content"))
    puts Content::Importer.call(root)
  rescue Content::ImportError => error
    abort "Content import failed\n  #{error.message}"
  end
end
