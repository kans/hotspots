require 'sqlite3'

$db = SQLite3::Database.new('db.sqlite')
$db.execute "
CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY NOT NULL,
  org VARCHAR(40) NOT NULL,
  repo VARCHAR(40) NOT NULL,
  head VARCHAR(40) NOT NULL,
  UNIQUE(repo, org)
);"

$db.execute "
CREATE TABLE IF NOT EXISTS events (
  project_id REFERENCES projects(id) NOT NULL,
  time TIMESTAMP NOT NULL,
  sha VARCHAR(40),
  path TEXT NOT NULL,
  UNIQUE(sha, path)
);
"

module DB
  def DB.create_project(repo)
    begin
      $db.execute "INSERT INTO PROJECTS (org, repo, head) VALUES(?, ?, ?);", repo.org, repo.name, ""
    rescue SQLite3::ConstraintException
    end
  end
  def DB.add_events(fixes, org, name)
    id = $db.get_first_value "SELECT id FROM projects WHERE org=? and repo=?;", org, name 
    query = "INSERT INTO events "
    args = []
    first_time = true
    fixes.each do |fix|
      if first_time
        query << " SELECT ? AS 'project_id', ? AS 'sha', ? AS 'time', ? AS 'path' "
        first_time = false
      else
        query << " UNION SELECT ?, ?, ?, ? "
      end
      args += [id, fix.sha, fix.date, fix.file]
      if args.length >900
        begin
          $db.execute query, args
        rescue SQLite3::ConstraintException => e 
          puts e
        end
        args=[]
        query = "INSERT INTO events "
        first_time = true
      end
    end
    unless args.empty?
      begin
        $db.execute query, args
      rescue SQLite3::ConstraintException => e 
        puts e
      end
    end
  end
end