require 'json'
require 'optparse'
require 'bundler'
require 'pathname'
require 'set'

module Srclib
  class Scan
    def self.summary
      "discover Ruby gems/apps in a dir tree"
    end

    def option_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: scan [options]"
        opts.on("--repo URI", "URI of repository") do |v|
          @repo = v
        end
        opts.on("--subdir DIR", "path of current dir relative to repo root") do |v|
          Dir.chdir(v)
        end
      end
    end

    def run(args)
      option_parser.order!

      pre_wd = Pathname.pwd

      # Keep track of already discovered files in a set
      discovered_deps, discovered_files = Set.new, Set.new
      source_units = []

      find_gemspecs(pre_wd).each do |gemspec|
        Dir.chdir(File.dirname(gemspec))

        if File.exist?("Gemfile")
          Bundler.definition.specs # force evaluation of lazy specs
          Bundler.definition.resolve.each do |dep|
            next if not discovered_deps.add? dep.name
            next if dep.default_gem?

            Dir.chdir(dep.full_gem_path)
            source_units << unit_from_spec(
              dep,
              dep.full_gem_path,
              discovered_files)
          end
        else
          # just the one gem
          source_units << unit_from_spec(
            Gem::Specification.load(gemspec),
            File.dirname(gemspec),
            discovered_files)
        end

      end

      find_scripts(pre_wd).
        reject {|script| discovered_files.include? script}.
        each do |script|
          source_units << {
            'Name' => File.basename(gemspec).sub(/.rb$/, ''),
            'Type' => 'rubyprogram',
            'Dir' => File.dirname(script),
            'Files' => [script],
            'Dependencies' => nil, #TODO(rameshvarun): Aggregate dependencies from all of the scripts
            'Data' => {
              'name' => 'rubyscripts',
              'files' => [script],
            },
            'Ops' => {'depresolve' => nil, 'graph' => nil},
          }
        end

      source_units.each {|u| u['Repo'] = @repo } if not @repo.nil?
      puts JSON.generate(source_units.sort_by { |a| a['Name'] })
    end

    private

    def find_gemspecs dir
      Dir.glob(File.join(File.expand_path(dir), "**/*.gemspec")).sort
    end

    # Finds all scripts that are not accounted for in the existing set of found gems
    # @param dir [String] The directory in which to search for scripts
    # @param gem_units [Array] The source units that have already been found.
    def find_scripts dir
      scripts = []

      dir = File.expand_path(dir)
      Dir.glob(File.join(dir, "**/*.rb")).map do |script_file|
        scripts << script_file
      end

      scripts
    end

    def unit_from_spec spec, dir, discovered_files
      files = spec.files.select { |f| f.end_with? '.rb'}.map{|f| File.join(dir, f) }

      spec.require_paths.each do |path|
        files += Dir.glob(File.join(dir, path, '**', '*.rb'))
      end

      spec.executables.each do |exe|
        files << File.join(dir, spec.bindir, exe)
      end

      files.sort!
      files.uniq!
      files.each {|f| discovered_files.add f}

      {
        'Name' => spec.name,
        'Type' => 'rubygem',
        'Dir' => dir,
        'Files' => files,
        'Dependencies' => spec.dependencies.map {|d| [d.name, d.requirement.to_s] },
        'Data' => {},
        'Ops' => {'depresolve' => nil, 'graph' => nil},
      }
    end
  end
end
