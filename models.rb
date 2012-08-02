require 'sequel'

$DB = Sequel.sqlite('db.sqlite')

$DB.create_table? :projects do
  primary_key :id
  String :access_token
  String :org, null: false
  String :name, null: false
  # TODO: remove me?
  String :last_sha
  unique [:org, :name]
end

$DB.create_table? :events do
  foreign_key :project_id, :projects, null: false
  DateTime :date, null: false
  String :sha
  String :file, null: false
  unique [:sha, :file]
end

Dir[File.dirname(__FILE__) + '/models/*.rb'].each {|file| require file }
