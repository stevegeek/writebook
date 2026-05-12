# Add `config/locales/` to I18n's load path. Marten 0.6.3's auto-discovery
# uses `Marten.root` whose resolution depends on launch context; specifying
# the path explicitly is more reliable.
locales_path = Path["config/locales"].expand.to_s
I18n.config.loaders << I18n::Loader::YAML.new(locales_path) if Dir.exists?(locales_path)
