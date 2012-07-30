require 'sequel'

$DB.create_table? :events do
  foreign_key :project_id, :projects, null: false
  DateTime :date, null: false
  String :sha
  String :file, null: false
  unique [:sha, :file]
end
