#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'ostruct'
require 'pp'


########## UTILS #############

def mkget(dict, type, name, extra = {})
  dict[type] ||= {}
  it = dict[type][name]
  if !it
    it = {:type => type, :name => name}
    dict[type][name] = it
  end
  it.merge!(extra)
  it
end

def with_context(dict, it)
  dict[:context] ||= []
  dict[:context].push it
  begin
    yield it
  rescue
    puts "Context:"
    dict[:context].each {|i| puts "  " + i.to_s}
    raise
  end
ensure
  dict[:context].pop
end


########## LOAD DATA #############

def load_data(playbook_dir)
  dict = {}
  Dir.new(playbook_dir).find_all { |file|
    /.yml$/i === file.downcase
  }.inject({}) { |map, file|
    File.open(File.join(playbook_dir, file)) { |fd|
      map[file.sub(/.yml$/, '')] = YAML.load(fd)
    }
    map
  }.map { |name, data|
    mk_playbook(dict, playbook_dir, name, data)
  }
  dict
end

def mk_playbook(dict, basedir, name, data)
  playbook = mkget(dict, :playbook, name)
  with_context dict, playbook do
    playbook[:roles] = (data[0]['roles'] || []).map {|role|
        mk_role(dict, basedir, role)
      }.uniq  # FIXME
    playbook[:tasks] = (data[0]['tasks'] || []).map {|task_h|
        mk_task(dict, basedir, task_h['include'])
      }.compact.uniq  # FIXME
  end
  playbook
end

def mk_role(dict, basedir, name)
  role = mkget(dict, :role, name, {:dep => false})
  with_context dict, role do
    roledir = File.join(basedir, "roles", name)
    if !File.directory? roledir
      raise "Missing roledir: "+ roledir
    end
    taskdir = File.join(roledir, "tasks")
    if File.directory? taskdir
      role[:tasks] = Dir.new(taskdir).
        find_all {|f| f =~ /.yml$/ }.
        reject {|n| n =~ /^_|^main.yml$/ }.
        map {|n| File.join(taskdir, n) }.
        map {|p| mk_task(dict, taskdir, p) }.
        uniq  # FIXME
    end

    metafile = File.join(roledir, "meta", "main.yml")
    if File.file? metafile
      meta = nil
      File.open(metafile) {|fd|
        meta = YAML.load(fd)
      }
      role[:role_deps] = (meta['dependencies'] || []).
        map {|dep| dep['role'] }.
        map {|dep| mkget(dict, :role, dep) }
      role[:role_deps].each {|dep|
        if dep[:dep] == nil
          dep[:dep] = true
        end
      }
    end
  end
  role
end

def mk_task(dict, basedir, filename)
  if filename =~ %r!roles/([[:alnum:]_-]+)/tasks/([[:alnum:]_-]+).yml!
    mkget(dict, :task, $2 + " / " + $1, {:role => $1})
  else
    raise "Bad task: "+ filename
  end
end


########## GRAPHIFY ###########

def graphify(dict)
  g = Graph.new
  g[:rankdir] = 'LR'

  [[:playbook, {:shape => 'folder'}],
   [:role, {:shape => 'octagon'}],
   [:task, {:shape => 'oval'}]].each {|type, attrs|
    dict[type].each_pair {|name, it|
      node = g.get_or_make(name)
      it[:node] = node
      attrs.each_pair {|k,v| node[k] = v }
    }
  }
  dict[:playbook].each_value {|playbook|
    with_context dict, playbook do
      (playbook[:roles] || []).each {|role|
        g.add GEdge[playbook[:node], role[:node]]
      }
      (playbook[:tasks] || []).each {|task|
        g.add GEdge[playbook[:node], task[:node], {:style => 'dashed', :color => 'blue'}]
      }
    end
  }
  dict[:role].each_value {|role|
    with_context dict, role do
      (role[:tasks] || []).each {|task|
        g.add GEdge[role[:node], task[:node]]
      }
      (role[:role_deps] || []).each {|dep|
        g.add GEdge[role[:node], dep[:node], {:color => 'hotpink'}]
      }
    end
  }
  dict[:role].values.find_all {|role| role[:dep] }.
      each {|role|
    role[:node][:style] = 'filled'
    role[:node][:fillcolor] = 'plum'
  }

  g
end


########## DECORATE ###########

# This is accessed as a global from graph_viz.rb, EWW
def rank_node(node)
  case node[:shape]
  when /folder/ then :source
  when /oval/ then :sink
  end
end

########## RENDER #############

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

def en_join(a)
  case a.count
  when 0 then "none"
  when 1 then a.first
  else
    a.slice(0, a.count-1).join(", ") +" and #{a.last}"
  end
end


########## OPTIONS #############

options = OpenStruct.new
options.format = :hot
options.output_filename = "viz.html"
OptionParser.new do |o|
  o.banner = "Usage: ansible-viz.rb [options] <path-to-playbooks>"
  o.on("-o", "--output [FILE]", "Where to write output") do |fname|
    options.output_filename = fname
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

if !File.directory? options.playbook_dir
  raise "Not a dir: #{options.playbook_dir}"
end

dict = load_data(options.playbook_dir)
graph = graphify(dict)
write(graph, options.output_filename)