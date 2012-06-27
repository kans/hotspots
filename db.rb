require 'sqlite3'

$db = SQLite3::Database.new('db.sqlite')
$db.execute "
CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY NOT NULL,
  org VARCHAR(40) NOT NULL,
  repo VARCHAR(40) NOT NULL,
  last_sha VARCHAR(40),
  UNIQUE(repo, org)
);"

$db.execute "
CREATE TABLE IF NOT EXISTS events (
  project_id REFERENCES projects(id) NOT NULL,
  date TIMESTAMP NOT NULL,
  sha VARCHAR(40),
  file TEXT NOT NULL,
  UNIQUE(sha, file)
);
"

module DB
  def DB.create_project(repo)
    begin
      $db.execute "INSERT INTO PROJECTS (org, repo, last_sha) VALUES(?, ?, ?);", repo.org, repo.name, nil
    rescue SQLite3::ConstraintException
    ensure
      id = $db.get_first_value "SELECT id FROM projects WHERE org=? and repo=?;", repo.org, repo.name
      return id
    end
  end

  def DB.get_last_sha(project_id)
    $db.get_first_value "SELECT last_sha FROM projects WHERE id=?;", project_id
  end

  def DB.multiple_insert(table, cols, values)
    args = []
    escape_string = (["?"] * cols.length).join ','
    query = "INSERT INTO #{table} (#{cols.join ','}) "
    first_time = true
    debugger
    unless values.empty?
      if first_time
        first_time = false
      else
        query << " UNION "
      end
      query << " SELECT #{escape_string} "
      args += values.shift.to_a
      if args.length - cols.length <= 999
        multiple_insert table, cols, values
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

  def DB.add_events(fixes, last_sha, project_id)
    self.multiple_insert 'events', ['project_id', 'sha', 'date', 'file'], fixes
    # args = []
    # first_time = true

    # query = "INSERT INTO events (project_id, sha, time, path) "
    # fixes.each do |fix|
    #   if first_time
    #     first_time = false
    #   else
    #     query << " UNION "
    #   end
    #   query << " SELECT ?, ?, ?, ? "
    #   args += [project_id, fix.sha, fix.date, fix.file]
    #   if args.length >900
    #     begin
    #       $db.execute query, args
    #     rescue SQLite3::ConstraintException => e 
    #       puts e
    #     end
    #     args=[]
    #     query = "INSERT INTO events (project_id, sha, time, path) "
    #     first_time = true
    #   end
    # end
    # unless args.empty?
    #   begin
    #     $db.execute query, args
    #   rescue SQLite3::ConstraintException => e 
    #     puts e
    #   end
    # end
    # $db.execute "UPDATE projects SET last_sha=? WHERE id =?;", last_sha, project_id
  end

  def DB.get_events (project_id)
   return $db.query "SELECT date, sha, file FROM events WHERE project_id=?", project_id
  end
end