require 'yaml'
###
# GPS Geo Planning System
# This module is designed as a higher abstration above the "resources" level
# The abstration is built for engineers to use so is in their vocabulary
# As each engineering team is different GPS is only building blocks
# GPS is not a complete solution
###
class GeoEngineer::GPS
  class NotFoundError < StandardError; end
  class NotUniqueError < StandardError; end
  class BadQueryError < StandardError; end
  class BadReferenceError < StandardError; end
  class GPSProjetNotFound < StandardError; end
  class NodeTypeNotFound < StandardError; end
  class MetaNodeError < StandardError; end
  class LoadError < StandardError; end

  GPS_FILE_EXTENSTION = ".gps.yml".freeze

  REFERENCE_SYNTAX = %r{
    ^(?!arn:aws:)                           # Make sure we do not match AWS ARN's
    (?<project>[a-zA-Z0-9\-_/*]*):         # Match the project name (optional)
    (?<environment>[a-zA-Z0-9\-_*]*):      # Match the environment (optional)
    (?<configuration>[a-zA-Z0-9\-_*]*):    # Match the configuration (optional)
    (?<node_type>[a-zA-Z0-9\-_]+):         # Match the node_type (required), does not support `*`
    (?<node_name>[a-zA-Z0-9\-_/*.]+)       # Match the node_name (required)
    (                                       # The #<resource>.<attribute> is optional
      [#](?<resource>[a-zA-Z0-9_]+)         # Match the node resource (optional)
      ([.](?<attribute>[a-zA-Z0-9_]+))?     # Match the resource attribute, requires resource (optional)
    )?
    $
  }x

  class << self
    attr_reader :singleton
  end

  class << self
    attr_writer :singleton
  end

  ###
  # HASH METHODS
  ###

  # remove_ removes all keys starting with `_`
  def self.remove_(hash)
    hash = hash.dup
    hash.each_pair do |key, value|
      hash.delete(key) && next if key.to_s.start_with?("_")
      hash[key] = remove_(value) if value.is_a?(Hash)
    end
    hash
  end

  def self.deep_dup(object)
    JSON.parse(object.to_json)
  end

  ###
  # END OF HASH METHODS
  ###

  ###
  # Search Methods
  ###

  # where returns multiple nodes
  def self.where(nodes, query = "*:*:*:*:*")
    search(nodes, query)
  end

  # find a node from nodes
  def self.find(nodes, query = "*:*:*:*:*")
    query_nodes = search(nodes, query)
    raise NotFoundError, "for query #{query}" if query_nodes.empty?
    raise NotUniqueError, "for query #{query}" if query_nodes.length > 1
    query_nodes.first
  end

  def self.split_query(query)
    query_parts = query.split(":")
    raise BadQueryError, "for query #{query}" if query_parts.length != 5
    query_parts
  end

  def self.search(nodes, query)
    project, environment, config, node_type, node_name = split_query(query)
    nodes.select { |n| n.match(project, environment, config, node_type, node_name) }
  end

  def self.dereference(nodes, reference)
    components = reference.match(REFERENCE_SYNTAX)
    return reference unless components

    query = query_from_reference(reference)
    nodes = where(nodes, query)
    raise NotFoundError, "for reference: #{reference}" if nodes.empty?

    nodes.map do |node|
      next node unless components["resource"]
      method_name = "#{components['resource']}_ref"
      attribute = components["attribute"] || 'id'

      unless node.respond_to?(method_name)
        raise BadReferenceError, "#{query} does not have resource: #{components['resource']}"
      end

      node.send(method_name, attribute)
    end
  end

  def self.query_from_reference(reference)
    components = reference.match(REFERENCE_SYNTAX)
    [
      components["project"],
      components["environment"],
      components["configuration"],
      components["node_type"],
      components["node_name"]
    ].join(":")
  end

  ###
  # End of Search Methods
  ###

  def self.json_schema
    node_names = {
      "type":  "object",
      "additionalProperties" => {
        "type":  "object"
      }
    }

    node_types = {
      "type":  "object",
      "additionalProperties" => node_names
    }

    configurations = {
      "type":  "object",
      "additionalProperties" => node_types
    }

    environments = {
      "type":  "object",
      "additionalProperties" => configurations,
      "minProperties": 1
    }

    environments
  end

  # Load
  def self.load_gps_file(gps_instance, gps_file)
    raise "The file \"#{gps_file}\" does not exist" unless File.exist?(gps_file)

    # partial file name is the
    partial_file_name = gps_file.gsub(".gps.yml", ".rb")

    if File.exist?(partial_file_name)
      # if the partial file exists we load the file directly
      # This will create the GPS resources
      require "#{Dir.pwd}/#{partial_file_name}"
    else
      # otherwise initalize for the partial directly here
      gps_instance.partial_of(partial_file_name)
    end
  end

  def load_gps_file(gps_file)
    GeoEngineer::GPS.load_gps_file(self, gps_file)
  end

  # Parse
  def self.parse_dir(dir)
    # Load, expand then merge all yml files
    base_hash = Dir["#{dir}**/*#{GPS_FILE_EXTENSTION}"].reduce({}) do |projects, gps_file|
      begin
        # Merge Keys don't work with YAML.safe_load
        # since we are also loading Ruby safe_load is not needed
        gps_text = ERB.new(File.read(gps_file)).result(binding).to_s
        gps_hash = YAML.load(gps_text)
        # remove all keys starting with `_` to remove paritals
        gps_hash = remove_(gps_hash)
        JSON::Validator.validate!(json_schema, gps_hash)

        # project name is the path + file
        project_name = gps_file.sub(dir, "")[0...-GPS_FILE_EXTENSTION.length]

        projects.merge({ project_name.to_s => gps_hash })
      rescue StandardError => e
        raise LoadError, "Could not load #{gps_file}: #{e.message}"
      end
    end

    GeoEngineer::GPS.new(base_hash)
  end

  attr_reader :nodes
  def initialize(base_hash)
    # Base Hash is the unedited input, useful for debugging
    @base_hash = base_hash

    # First Deep Dup to ensure seperate objects
    # Dup to ensure string keys and to expeand
    projects_hash = GeoEngineer::GPS.deep_dup(base_hash)

    # expand meta nodes, this takes nodes and expands them
    projects_hash = expand_meta_nodes(projects_hash)

    # build the node instances and add them to all nodes
    @nodes = build_nodes(projects_hash)

    # validate all nodes
    @nodes.each(&:validate) # this will validate and expand based on their json schema
  end

  def find(query)
    GeoEngineer::GPS.find(@nodes, query)
  end

  def where(query)
    GeoEngineer::GPS.where(@nodes, query)
  end

  def dereference(reference)
    GeoEngineer::GPS.dereference(@nodes, reference)
  end

  def to_h
    GeoEngineer::GPS.deep_dup(@base_hash)
  end

  def expanded_hash
    expanded_hash = {}
    @nodes.each do |n|
      proj = expanded_hash[n.project] ||= {}
      env = proj[n.environment] ||= {}
      conf = env[n.configuration] ||= {}
      nt = conf[n.node_type] ||= {}
      nt[n.node_name] ||= n.attributes
    end
    expanded_hash
  end

  def loop_projects_hash(projects_hash)
    # TODO: validate the strucutre before this
    projects_hash.each_pair do |project, environments|
      environments.each_pair do |environment, configurations|
        configurations.each_pair do |configuration, nodes|
          nodes.each_pair do |node_type, node_names|
            node_names.each_pair do |node_name, attributes|
              node_type_class = find_node_class(node_type)
              yield node_type_class.new(project, environment, configuration, node_name, attributes)
            end
          end
        end
      end
    end
  end

  def expand_meta_node(node)
    node.validate # ensures that the meta node has expanded and has correct attributes
    children_nodes = GeoEngineer::GPS.deep_dup(node.build_nodes)

    children_nodes.reduce(children_nodes.clone) do |expanded, (node_type, node_names)|
      node_names.reduce(expanded.clone) do |inner_expanded, (node_name, attributes)|
        node_type_class = find_node_class(node_type)
        node = node_type_class.new(node.project, node.environment, node.configuration, node_name, attributes)
        next inner_expanded unless node.meta?

        deep_merge(inner_expanded, expand_meta_node(node))
      end
    end
  end

  def expand_meta_nodes(projects_hash)
    # We dup the original hash because we cannot edit and loop over it at the same time
    loop_projects_hash(GeoEngineer::GPS.deep_dup(projects_hash)) do |node|
      next unless node.meta?

      # find the hash to edit
      nodes = projects_hash.dig(node.project, node.environment, node.configuration)

      # node_type => node_name => attrs
      built_nodes = expand_meta_node(node)

      built_nodes.each_pair do |built_node_type, built_node_names|
        nodes[built_node_type] ||= {}
        built_node_names.each_pair do |built_node_name, built_attributes|
          # Error if the meta-node is overwriting an existing node
          already_built_error = "\"#{node.node_name}\" overwrites node \"#{built_node_name}\""
          raise MetaNodeError, already_built_error if nodes[built_node_type].key?(built_node_name)
          # append to the hash
          nodes[built_node_type][built_node_name] = built_attributes
        end
      end
    end

    projects_hash
  end

  # This merges a set of deeply nested hashes
  def deep_merge(a = {}, b = {})
    a.merge(b) do |key, value_a, value_b|
      if value_a.is_a?(Hash) || value_b.is_a?(Hash)
        deep_merge(value_a, value_b)
      else
        value_b
      end
    end
  end

  def build_nodes(projects_hash)
    all_nodes = []
    # This is a lot of assumptions

    loop_projects_hash(projects_hash) do |node|
      all_nodes << node
    end

    all_nodes
  end

  # This method takes the file name of the geoengineer project file
  # it calculates the location of the gps file
  def partial_of(file_name, &block)
    org_name, project_name = file_name.gsub(".rb", "").split("/")[-2..-1]
    full_name = "#{org_name}/#{project_name}"

    @created_projects ||= {}
    return if @created_projects[full_name] == true
    @created_projects[full_name] = true

    create_project(org_name, project_name, env, &block)
  end

  def create_project(org, name, environment, &block)
    project_name = "#{org}/#{name}"
    environment_name = environment.name
    project_environments = project_environments(project_name)

    raise GPSProjetNotFound, "project not found \"#{project_name}\"" unless project?(project_name)

    project = environment.project(org, name) do
      environments project_environments
    end

    # create all resources for projet
    project_nodes = GeoEngineer::GPS.where(@nodes, "#{project_name}:#{environment_name}:*:*:*")
    project_nodes.each do |n|
      n.all_nodes = @nodes
      n.create_resources(project) unless n.meta?
    end

    project_configurations(project_name, environment_name).each do |configuration|
      # yeild to the given block nodes per-config
      nw = GeoEngineer::GPS::NodesContext.new(project_name, environment_name, configuration, @nodes)
      yield(project, configuration, nw) if block_given? && project_nodes.any?
    end

    project
  end

  def project?(project)
    !!@base_hash[project]
  end

  def project_environments(project)
    @base_hash.dig(project)&.keys || []
  end

  def project_configurations(project, environment)
    @base_hash.dig(project, environment)&.keys || []
  end

  # find node type
  def find_node_class(type)
    clazz_name = type.split('_').collect(&:capitalize).join
    module_clazz = "GeoEngineer::GPS::Nodes::#{clazz_name}"
    return Object.const_get(module_clazz) if Object.const_defined? module_clazz

    raise NodeTypeNotFound, "not found node type '#{type}' for '#{clazz_name}' or '#{module_clazz}'"
  end
end
