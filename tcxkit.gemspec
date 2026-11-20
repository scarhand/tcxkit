# frozen_string_literal: true

require_relative "lib/tcxkit/version"

Gem::Specification.new do |spec|
  spec.name = "tcxkit"
  spec.version = TcxKit::VERSION
  spec.authors = ["The tcxkit contributors"]
  spec.summary = "A read-only, streaming Ruby parser for Garmin TCX files"
  spec.description = "Reads Training Center Database v2 (.tcx) files safely and lazily, " \
                     "keeping every value as written, with an activity view shared with fitkit and gpxkit."
  spec.homepage = "https://github.com/scarhand/tcxkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "README.md", "SPECIFICATION.md", "CHANGELOG.md", "LICENSE"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "nokogiri", "~> 1.16"
  spec.add_development_dependency "minitest", ">= 5.0", "< 7.0"
  spec.add_development_dependency "rake", ">= 13.0"
end
