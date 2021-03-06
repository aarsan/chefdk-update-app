#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2015 Fletcher Nichol
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "pathname"
require "optparse"

App = Struct.new(:name, :url, :bundle_without) do
  def to_s
    name
  end
end

CHEFDK_APPS = [
  App.new(
    "berkshelf",
    "https://github.com/berkshelf/berkshelf.git",
    "guard test development"
  ),
  App.new(
    "chef",
    "https://github.com/chef/chef.git",
    "server docgen test development"
  ),
  App.new(
    "chef-dk",
    "https://github.com/chef/chef-dk.git",
    "dev test development"
  ),
  App.new(
    "chef-vault",
    "https://github.com/Nordstrom/chef-vault.git",
    "test development"
  ),
  App.new(
    "foodcritic",
    "https://github.com/acrmp/foodcritic.git",
    "test development"
  ),
  App.new(
    "ohai",
    "https://github.com/chef/ohai.git",
    "test development"
  ),
  App.new(
    "test-kitchen",
    "https://github.com/test-kitchen/test-kitchen.git",
    "guard test development"
  )
].freeze

class Updater
  attr_reader :app, :ref

  def initialize(options)
    @app = options[:app]
    @ref = options[:ref]
  end

  def start
    if !windows? && Process.uid != 0
      abort "#{$0} needs to be run as root user or with sudo"
    end

    banner("Cleaning #{app} checkout")
    app_dir.rmtree if app_dir.directory?

    banner("Cloning #{app} from #{app.url}")
    run("git clone #{app.url} #{app_dir}")

    banner("Checking out #{app} to #{ref}")
    Dir.chdir(app_dir) do
      run("git checkout #{ref}")
    end

    banner("Installing dependencies")
    Dir.chdir(app_dir) do
      ruby("#{bin_dir.join("bundle")} install --without #{app.bundle_without}")
    end

    banner("Updating appbundler binstubs for #{app}")
    Dir.chdir(app_dir) do
      ruby("#{bin_dir.join("appbundler")} #{app_dir} #{chefdk.join("bin")}")
    end

    banner("Finished!")
  end

  private

  ENV_KEYS = %w[
    BUNDLE_BIN_PATH BUNDLE_GEMFILE GEM_HOME GEM_PATH GEM_CACHE RUBYOPT
  ].freeze

  def app_dir
    chefdk.join("embedded/apps/#{app}")
  end

  def banner(msg)
    puts "-----> #{msg}"
  end

  def bin_dir
    chefdk.join("embedded/bin")
  end

  def chefdk
    if windows?
      Pathname.new(File.join(ENV["SYSTEMDRIVE"], "opscode", "chefdk"))
    else
      Pathname.new("/opt/chefdk")
    end
  end

  def ruby(script)
    ruby = bin_dir.join("ruby").to_s.tap { |p| p.concat(".exe") if windows? }

    run([ruby, script].join(" "))
  end

  def run(cmd)
    ENV_KEYS.each { |key| ENV["_YOLO_#{key}"] = ENV[key]; ENV.delete(key) }
    system(cmd) or raise("Command [#{cmd}] failed!")
    ENV_KEYS.each { |key| ENV[key] = ENV.delete("_YOLO_#{key}") }
  end

  def windows?
    @windows ||= RUBY_PLATFORM =~ /mswin|mingw|windows/
  end
end

class CLI
  def self.options
    new.options
  end

  attr_reader :options, :parser

  def initialize
    @options = Hash.new
    @parser = OptionParser.new { |opts|
      opts.banner = "Usage: #{$0} APP_NAME [options]"
      opts.on("-r REF", "--ref REF", "Git reference (branch, tag, sha, etc.)") do |r|
        options[:ref] = r
      end
      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
      opts.separator("")
      opts.separator("App names:")
      CHEFDK_APPS.each { |a| opts.separator("    * #{a.name}") }
    }
    @parser.parse!
    validate!
  end

  def validate!
    die("APP_NAME is required") if ARGV.empty?
    options[:app] = CHEFDK_APPS.find { |a| a.name == ARGV.first }
    die("Invalid APP_NAME: #{ARGV.first}") if options[:app].nil?
    die("--ref flag is required") if options[:ref].nil?
  end

  def die(msg)
    $stderr.puts msg
    $stderr.puts parser
    exit 1
  end
end

Updater.new(CLI.options).start
