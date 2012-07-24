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
      return $db.get_first_value "SELECT id FROM projects WHERE org=? and repo=?;", repo.org, repo.name
    end
  end

  def DB.get_last_sha(project_id)
    return $db.get_first_value "SELECT last_sha FROM projects WHERE id=?;", project_id
  end

  def DB.multiple_insert(table, values)
    args = []
    cols = []
    throw Exception.new("Give me a something") if values.empty?
    values[0].each_pair{|k,v| cols.push k}
    escape_string = (["?"] * cols.length).join ','
    query = "INSERT INTO #{table} (#{cols.join ','}) "
    first_time = true
    while not values.empty?
      if first_time
        first_time = false
      else
        query << " UNION "
      end
      query << " SELECT #{escape_string} "
      args += values.shift.to_a
      if args.length >= 999 - cols.length
        multiple_insert table, values
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
    return if fixes.length <= 0
    self.multiple_insert 'events', fixes
    $db.execute "UPDATE projects SET last_sha=? WHERE id =?;", last_sha, project_id
  end

  def DB.get_events (project_id)
    db_events = $db.query "SELECT date, sha, file FROM events WHERE project_id=? order by date desc;", 
      project_id
    container = Struct.new(*db_events.columns.collect{|val| val.to_sym})
    events = []
    db_events.each do |event|
      events << container.new(*event)
    end
    return events
  end
end
