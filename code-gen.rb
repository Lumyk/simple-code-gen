require "graphql/libgraphqlparser"
require 'json'
require 'optparse'
require 'ostruct'

class OptparseExample

  def self.parse(args)
    options = OpenStruct.new
    options.graphql = false
    options.list = false
    options.type = :graphql

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: code-gen.rb [options]"

      opts.separator ""
      opts.separator "Require options:"

      opts.on("-s","--schema [PATH]", "Path to graphql schema (*.json)") do |path|
        options.schema = path
      end

      opts.separator ""
      opts.separator "Specific options:"

      opts.on("-g", "--graphql [PATHS]", Array,
              "Paths to *.graphql files, example: '-g path1,path2,path3'") do |paths|
        options.graphql = true
        options.paths = paths
      end

      opts.on("--type [TYPE]", [:graphql, :schema],
              "Generation type (graphql, schema), default - graphql") do |t|
        options.type = t
      end

      opts.on("--classes [NAME]", Array,
              "Classes names for generation, used only for 'schema' type") do |classes|
        options.classes = true
        options.classes = classes
      end

      opts.separator ""
      opts.separator "Common options:"

      opts.on_tail("--list", "List of types(Classes) in GraphQL schema") do
        options.list = true
      end

      opts.on_tail("-h", "--help", "Help") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end

end

class String
  def camel_case_lower
    self.split('_').inject([]){ |buffer,e| buffer.push(buffer.empty? ? e : e.capitalize) }.join
  end
end

def parseGQLS(input_array)
  def parse_graphql_data(q, child_fields, child_type, result)
    if q.selections.length != 0
      q.selections.each do |q|
        if child_fields == nil then
          req = $query_types_fields[q.name]
          type = req["type"]
          child_name = type["name"]
          if child_name == nil
            child_name = type.dig("ofType.name")
          end
          if child_name != ""
            child_fields_ = $query_types[child_name]["fields"].map{ |v| [v["name"], v] }.to_h
            result[child_name] = []
            parse_graphql_data(q, child_fields_, child_name, result)
          end
        else
          virebles = result[child_type]
          field_type = child_fields[q.name]["type"]
          field_type_kind = field_type["kind"]
          type = "UnnownType"
          is_optional = true
          if field_type_kind == "SCALAR"
            type = "#{field_type["name"]}" if field_type["name"]
          elsif field_type_kind == "NON_NULL"
            type = field_type.dig("ofType.name") if field_type.dig("ofType.name")
            is_optional = false
          end
          virebles << { "name" => q.name, "type" =>  type, "is_optional" => is_optional}
        end
      end
    end
  end

  def structurize_data_for_class(classes_info)
    result = Hash.new
    classes_info.each do |key, vairebles|
      data = {
        "object_vairebles" => [],
        "from_dict_mapping" => [],
        "table_fields" => [],
        "row_mapping" => [],
        "row_mapping_with_table" => [],
        "create_table" => [],
        "inset_mapping" => [],
        "update_mapping" => [],
        "inset_from_dict_mapping" => []
      }
      vairebles.each do |vaireble|
        name = vaireble["name"]
        camel_name = name.camel_case_lower
        type = vaireble["type"].gsub("Float", "Double")
        is_optional = vaireble["is_optional"]
        optional = is_optional ? "?" : ""
        if type == "ID"
          type = "Int"
          data["from_dict_mapping"] << "self.#{camel_name} = try mapper.value(key: \"#{name}\", #{is_optional == true ? "transformOptionalType" : "transformType"}: TransformTypes.stringToInt)"
          data["inset_from_dict_mapping"] << "#{camel_name} <- try mapper.value(key: \"#{name}\", #{is_optional == true ? "transformOptionalType" : "transformType"}: TransformTypes.stringToInt, type: #{type}#{optional}.self)"
          if name == "id"
            data["create_table"] << "tableBuilder.column(#{camel_name}, primaryKey: true)"
          else
            data["create_table"] << "tableBuilder.column(#{camel_name})"
          end
        else
          if type == "JSON"
            data["inset_from_dict_mapping"] << "#{camel_name} <- try? encode(try mapper.value(key: \"#{name}\", type: JSON?.self))"
          else
            data["inset_from_dict_mapping"] << "#{camel_name} <- try mapper.value(key: \"#{name}\", type: #{type}#{optional}.self)"
          end
          data["from_dict_mapping"] << "self.#{camel_name} = try mapper.value(key: \"#{name}\")"
          data["create_table"] << "tableBuilder.column(#{camel_name})"
        end
        if type == "JSON"
          optional = "?"
          data["object_vairebles"] << "var #{camel_name}: #{type}#{optional}"
          type = "Data"
          data["table_fields"] << "static let #{camel_name} = Expression<#{type}#{optional}>(\"#{camel_name}\")"
          data["row_mapping"] << "self.#{camel_name} = try Type.decode(data: row.get(Type.#{camel_name}))"
          data["row_mapping_with_table"] << "self.#{camel_name} = try Type.decode(data: row.get(t[Type.#{camel_name}]))"
          data["inset_mapping"] << "Type.#{camel_name} <- try? Type.encode(self.#{camel_name})"
          data["update_mapping"] << "Type.#{camel_name} <- try? Type.encode(self.#{camel_name})"
        else
          data["object_vairebles"] << "var #{camel_name}: #{type}#{optional}"
          data["table_fields"] << "static let #{camel_name} = Expression<#{type}#{optional}>(\"#{camel_name}\")"
          data["row_mapping"] << "self.#{camel_name} = try row.get(Type.#{camel_name})"
          data["row_mapping_with_table"] << "self.#{camel_name} = try row.get(t[Type.#{camel_name}])"
          data["inset_mapping"] << "Type.#{camel_name} <- self.#{camel_name}"
          if name != "id"
            data["update_mapping"] << "Type.#{camel_name} <- self.#{camel_name}"
          end
        end
      end
      result[key] = data
    end
    return result
  end

  def generate_classes_file(structurize_data_for_class)
    structurize_data_for_class.each do |class_name, value|
      object_vairebles = value["object_vairebles"].join("\n    ")
      from_dict_mapping = value["from_dict_mapping"].join("\n        ")
      table_fields = value["table_fields"].join("\n    ")
      row_mapping = value["row_mapping"].join("\n            ")
      row_mapping_with_table = value["row_mapping_with_table"].join("\n                ")
      create_table = value["create_table"].join("\n        ")
      inset_mapping = value["inset_mapping"].join(",\n            ")
      update_mapping = value["update_mapping"].join(",\n            ")
      inset_from_dict_mapping = value["inset_from_dict_mapping"].join(",\n            ")

      path = "generated/#{class_name}"

      while File.file?("#{path}.swift") do
         path = "#{path}_"
      end

      puts path
      generated_file = File.open("#{path}.swift", 'w')
      class_body = "// generated class by https://github.com/Lumyk/simple-code-gen
import Foundation
import SQLite
import apollo_mapper
import sqlite_helper

class #{class_name}: Savable {
    #{object_vairebles}

    // Mappable
    required init(mapper: Mapper) throws {
        #{from_dict_mapping}
    }

    // Stored
    #{table_fields}

    required init(row: Row) throws {
        let Type = type(of: self)
        do {
            #{row_mapping}
        } catch {
            do {
                let t = Type.table
                #{row_mapping_with_table}
            } catch let error {
                throw error
            }
        }
    }

    static func tableBuilder(tableBuilder: TableBuilder) {
        #{create_table}
    }

    func insertMapper() -> [Setter] {
        let Type = type(of: self)
        return [
            #{inset_mapping}
        ]
    }

    static func insertMapper(mapper: Mapper) throws -> [Setter] {
        return [
            #{inset_from_dict_mapping}
        ]
    }

    func updateMapper() -> [Setter] {
        let Type = type(of: self)
        return [
            #{update_mapping}
        ]
    }
}"
      generated_file.write(class_body)
      generated_file.close()
    end
  end

  puts input_array

  input_array.each do |path|
    query_string = File.read(path)
    document = GraphQL::Libgraphqlparser.parse(query_string)
    query = document.definitions.first

    if query.operation_type == "query" then
      result = Hash.new
      parse_graphql_data(query, nil, nil, result)
      structurized_result = structurize_data_for_class(result)
      generate_classes_file(structurized_result)
    end
  end


end

class Hash
  def dig(dotted_path)
    parts = dotted_path.split '.', 2
    match = self[parts[0]]
    if !parts[1] or match.nil?
      return match
    else
      return match.dig(parts[1])
    end
  end
end


options = OptparseExample.parse(ARGV)

if options.schema == nil
  puts "'--schema' is require, put path to your GraphQL schema"
  exit
end

schema_string = File.read(options.schema)
schema = JSON.parse(schema_string)["data"]["__schema"]
query_type = schema.dig("queryType.name")
mutation_type = schema.dig("mutationType.name")

$query_types = schema["types"].map{ |v| [v["name"], v] }.to_h

if options.list
  puts schema["types"].map{ |v| v["name"] if v["kind"] != "SCALAR" }.compact
  exit
end

$query_types_fields = $query_types[query_type]["fields"].map{ |v| [v["name"], v] }.to_h

if options.type == :graphql && options.graphql == false
  puts "'-g' or '--graphql' is require for type 'graphql'"
  exit
elsif options.type == :graphql && options.graphql
  if options.paths.count != 0
    parseGQLS(options.paths)
    exit
  else
    puts "Can't find any *.graphql files"
    exit
  end
end
