# yomiagekun
読み上げくんv2のソースコードです

## つかいかた

### 依存関係のインストール
`bundle install`

### .envの作成
`config_sample.env`を`config.env`としてリネイムして編集

### データベースの準備
`ruby migrate_db.rb`

### 起動
`ruby -I dll main.rb`
