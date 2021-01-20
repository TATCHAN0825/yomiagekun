require 'active_record'
require 'yaml'
require './db/migrate/initial_schema'
require './db/migrate/create_prefixes'
require './db/migrate/create_dictionaries'

ActiveRecord::Base.establish_connection(YAML.load_file("./config/database.yml"))

# ゆるしてhack TODO
# ゆるしてhack TODO
# すきです TODO
# きらいになる TODO

unless ActiveRecord::Base.connection.table_exists?('users')
  puts "usersテーブルが存在しないためマイグレーションを行います..."
  InitialSchema::migrate(:up)
end

unless ActiveRecord::Base.connection.table_exists?('prefixes')
  puts "prefixesテーブルが存在しないためマイグレーションを行います..."
  CreatePrefixes::migrate(:up)
end
unless ActiveRecord::Base.connection.table_exists?('dictionaries')
  puts "dictionariesテーブルが存在しないためマイグレーションを行います..."
  CreateDictionaries::migrate(:up)
end