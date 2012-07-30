require 'sequel'

$DB = Sequel.sqlite('db.sqlite')

Dir[File.dirname(__FILE__) + '/models/*.rb'].each {|file| require file }
