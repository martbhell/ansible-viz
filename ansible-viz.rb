#!/usr/bin/ruby
# vim: set ts=2 sw=2 tw=100:

require 'rubygems'
require 'bundler/setup'

require 'mustache'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'ostruct'
require 'pp'

require './graphviz'
require './loader'
require './postprocessor'
require './resolver'
require './varfinder'
require './scoper'
require './grapher'
require './legend'


def get_options()
  options = OpenStruct.new
  options.format = :hot
  options.output_filename = "viz.html"
  options.show_vars = false
  options.show_usage = true

  OptionParser.new do |o|
    o.banner = "Usage: ansible-viz.rb [options] <path-to-playbooks>"
    o.on("-o", "--output [FILE]", "Where to write output") do |fname|
      options.output_filename = fname
    end
    o.on("--vars",
         "Include vars. Unused/undefined detection still has minor bugs.") do |val|
      options.show_vars = true
    end
    o.on("--no-usage",
         "Don't connect vars to where they're used.") do |val|
      options.show_usage = false
    end
    o.on_tail("-h", "--help", "Show this message") do
      puts o
      exit
    end
  end.parse!

  if ARGV.length != 1
    abort("Must provide the path to your playbooks")
  end
  options.playbook_dir = ARGV.shift

  options
end

def render(data, options)
  Postprocessor.new.process(data)
  Resolver.new.process(data)
  VarFinder.new.process(data)
  Scoper.new.process(data)
  grapher = Grapher.new
  g = grapher.graph(data, options)
  g[:rankdir] = 'LR'
  g.is_cluster = true

#  unlinked = grapher.extract_unlinked(g)
  legend = Legend.new.mk_legend

  superg = Graph.new
#  superg.add g, unlinked, legend
  superg.add g, legend
  superg[:rankdir] = 'LR'
  superg[:ranksep] = 2
  superg[:tooltip] = ' '
  superg
end

def write(graph, filename)
  Mustache.template_file = 'diagram.mustache'
  view = Mustache.new
  view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")

  view[:title] = "Ansible dependencies"
  view[:dotdata] = g2dot(graph)

  path = filename
  File.open(path, 'w') do |f|
    f.puts view.render
  end
end


########## OPTIONS #############

if __FILE__ == $0
  options = get_options()

  graph = render(Loader.new.load_dir(options.playbook_dir), options)
  write(graph, options.output_filename)
end
