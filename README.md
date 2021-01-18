# yomiagekun
読み上げくんv2のソースコードです

## つかいかた

### 依存関係のインストール
`bundle install`

### .envの作成
`sample.env`を`.env`としてコピーして編集

### データベースの準備
`ruby migrate_db.rb`

### 起動
`ruby -I dll main.rb`
