# Techniques, badges and all game content live as YAML in content/. Seeding runs the same
# idempotent importer as `bin/rails content:import`, so it's safe to run at any time.
puts Content::Import.new.run
