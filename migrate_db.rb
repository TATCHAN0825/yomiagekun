# データベースの初期化処理(マイグレーション)

require './db/connect'
require './db/migrate/initial_schema'

InitialSchema::migrate(:up)