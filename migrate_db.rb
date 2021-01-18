# データベースの初期化処理(マイグレーション)

require './db/connect'
require './db/migrate/initial_schema'
require './db/migrate/create_prefixes'

# 既にやってあるマイグレーションはコメントアウトする TODO: どうにかする
InitialSchema::migrate(:up)
CreatePrefixes::migrate(:up)
