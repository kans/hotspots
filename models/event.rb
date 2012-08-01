require 'sequel'

class Event < Sequel::Model
  many_to_one :project
  plugin :schema
  set_schema do
    foreign_key :project_id, :projects, null: false
    DateTime :date, null: false
    String :sha
    String :file, null: false
    unique [:sha, :file]
  end
end
