require 'active_record'
require 'yaml'
require './db/migrate/initial_schema'
require './db/migrate/create_prefixes'

ActiveRecord::Base.establish_connection(YAML.load_file("./config/database.yml"))

# ゆるしてhack TODO

unless ActiveRecord::Base.connection.table_exists?('users')
  puts "usersテーブルが存在しないためマイグレーションを行います..."
  InitialSchema::migrate(:up)
end

unless ActiveRecord::Base.connection.table_exists?('prefixes')
  puts "prefixesテーブルが存在しないためマイグレーションを行います..."
  CreatePrefixes::migrate(:up)
end