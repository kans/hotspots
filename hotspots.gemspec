Gem::Specification.new do |s|
  s.name = "hotspots"
  s.version = "0.0.1"
  s.summary = "Warn users about potentially buggy bits of code."
  s.add_dependency("grit", ">= 2.5.0")
  s.add_dependency("github_api", ">= 0.6.0")
  s.add_dependency("haml", ">= 3.1.6")
  s.add_dependency("sinatra", ">= 1.3.2")
  s.add_dependency("sqlite3", ">= 1.3.6")
end
