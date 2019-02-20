class GeoEngineer::GPS::Nodes::TestNode < GeoEngineer::GPS::Node
  define_resource "aws_elb", :elb
  define_resource "aws_elb", :elb_custom, ->(prefix, project, environment, configuration, node_name) {
    "#{prefix}@#{project}_#{environment}_#{configuration}_#{node_type}_#{node_name}"
  }

  def json_schema
    {
      "type":  "object",
      "additionalProperties" => false,
      "properties":  {
        "name":  {
          "type":  "string",
          "default":  "default"
        }
      }
    }
  end

  def create_resources(project)
    create_elb(project)
  end
end

class GeoEngineer::GPS::Nodes::TestMetaNode < GeoEngineer::GPS::MetaNode
  def json_schema
    {
      "type":  "object",
      "additionalProperties" => false,
      "properties":  {
        "name":  {
          "type":  "string",
          "default":  "default"
        }
      }
    }
  end

  # returns node_type -> node_name -> attrs
  def build_nodes
    {
      "test_node" => {
        node_name.to_s => {
          "name" => "awesome_#{attributes['name']}"
        }
      }
    }
  end
end

class GeoEngineer::GPS::Nodes::TestMetaMetaNode < GeoEngineer::GPS::MetaNode
  def json_schema
    {
      "type":  "object",
      "additionalProperties" => false,
      "properties":  {
        "name":  {
          "type":  "string",
          "default":  "default"
        }
      }
    }
  end

  # returns node_type -> node_name -> attrs
  def build_nodes
    {
      "test_meta_node" => {
        node_name.to_s => {
          "name" => "such_meta"
        }
      }
    }
  end
end
