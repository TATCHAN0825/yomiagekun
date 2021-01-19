require 'discordrb'
require 'json'
require 'dotenv'
require 'sqlite3'
require './db/connect'
require './models/user'
require './models/prefix'

Dotenv.load 'config.env'

# dotenvで必要な値を定義する
DOTENV_REQUIRED = ['TOKEN', 'OWNER_ID', 'DEFAULT_PREFIX', 'EVAL', 'DEBUG'].freeze

error_count = 0
DOTENV_REQUIRED.each do |required|
  if ENV[required].nil?
    error_count += 1
    puts "config.envに#{required}が無いよ"
  end
end
if error_count > 0
  puts 'config_sample.envを参考にconfig.envを編集してください'
  exit
end

# デバッグモードの場合のみActiveRecordのログを表示する
ActiveRecord::Base.logger = Logger.new(STDOUT) if ((DEBUG = ENV['DEBUG'].freeze) === 'true')

DATA = 'data'.freeze
PREFIXDATA = DATA + '\prefix.json'.freeze
MIGRATED_PREFIXDATA = DATA + '\migrated_prefix.json'.freeze
OPEN_JTALK = 'open_jtalk\bin\open_jtalk.exe'.freeze
VOICE = ' -m open_jtalk\bin\Voice'.freeze
VOICES = ['mei', 'takumi', 'slt'].freeze
EMOTIONS = ['normal', 'angry', 'sad', 'bashful', 'happy'].freeze
NORMAL = '\normal.htsvoice'.freeze
ANGRY = '\angry.htsvoice'.freeze
SAD = '\sad.htsvoice'.freeze
BASHFUL = '\bashful.htsvoice'.freeze
HAPPY = '\happy.htsvoice'.freeze
DIC = ' -x open_jtalk\bin\dic'.freeze
INPUT = 'open_jtalk\bin\input'.freeze
OUTPUT = 'open_jtalk\bin\output'.freeze
OWNER_ID = ENV['OWNER_ID'].to_i.freeze
DEFAULT_PREFIX = ENV['DEFAULT_PREFIX'].freeze
EVAL = ENV['EVAL'].freeze
$yomiage = []
$yomiagenow = [] # キュー消化中のリスト

$queue = Hash.new do |hash, key|
  hash[key] = []
end



# jsonのprefixからDBに移行
if File.exist?(PREFIXDATA)
  count = 0
  JSON.parse(File.read(PREFIXDATA)).each do |serverid, pre|
    Prefix.create(id: serverid, prefix: pre)
    count += 1
  end
  File.rename(PREFIXDATA, MIGRATED_PREFIXDATA)
  puts count.to_s + '件のprefixを移行しました'
end

def set_prefix(pre, serverid)
  if (prefix_model = Prefix.find_by(id: serverid)).nil?
    Prefix.create(id: serverid, prefix: pre) || prefix_model.errors.full_messages
  else
    prefix_model.prefix = pre
    prefix_model.save || prefix_model.errors.full_messages
  end
end

def get_prefix(serverid)
  Prefix.find_by(id: serverid)&.prefix || DEFAULT_PREFIX
end

def float?(value)
  /^[+-]?[0-9]*[.]?[0-9]+$/ =~ value
end

prefix_proc = proc do |message|
  prefix = get_prefix(message.server.id)
  message.content[prefix.size..-1] if message.content.start_with?(prefix)
end

def update_user_data(userid, voice = nil, emotion = nil, speed = nil, tone = nil)
  user = get_user_data(userid)
  user.voice = voice unless voice.nil?
  user.emotion = emotion unless emotion.nil?
  user.speed = speed.to_f unless speed.nil?
  user.tone = tone.to_f unless tone.nil?
  user.save #return
end

def get_user_data(userid)
  User.find_by(id: userid)
end

def register_user_data(userid)
  voice = %w[mei takumi].sample
  voiceemotion = { 'mei' => %w[angry bashful happy normal sad], 'takumi' => %w[normal angry sad happy], }
  emotion = voiceemotion[voice].sample
  User.create(id: userid, voice: voice, emotion: emotion, speed: 1.0, tone: 1.0)
end

def user_data_exists?(userid)
  User.exists?(id: userid)
end

def yomiage_exists?(serverid)
  $yomiage.include?(serverid)
end

def yomiage_start(serverid)
  $yomiage.push(serverid)
end

def yomiage_end(serverid)
  $yomiage.delete(serverid)
end

def yomiage_suru(event, msg, voice, userid, serverid)
  $queue[serverid].push(msg)

  unless $yomiagenow.include?(serverid) # キュー消化中でなかったら
    $yomiagenow.push(serverid)
    loop do
      text = $queue[serverid].shift
      yomiage(event, text, voice, userid, serverid)
      if $queue[serverid].size == 0
        $yomiagenow.delete(serverid)
        break
      end
    end
  end
end

def yomiage(event, msg, voice, userid, serverid)
  File.write("open_jtalk\\bin\\input\\v#{event.server.id}.txt", msg, encoding: Encoding::SJIS)
  user = get_user_data(userid)
  s = system(cmd = OPEN_JTALK + VOICE + '\\' + "#{user.voice}" + '\\' + "#{user.emotion}" +'.htsvoice' + DIC + ' -fm ' + "#{user.tone}" + ' -r ' + "#{user.speed}" + ' -ow ' + OUTPUT + '\v' + "#{serverid}.wav" + ' ' + INPUT + '\v' + "#{serverid}.txt")
  if s == true
    #voice_bot = event.voice
    voice.play_file(OUTPUT + '\v' + "#{serverid}" + '.wav')
  else
    event.respond('コマンド実行エラー')
    p cmd
  end
end


bot = Discordrb::Commands::CommandBot.new(token: ENV['TOKEN'], prefix: prefix_proc)

previous = Date.today
bot.disconnected do |_event|
  save
  puts 'ボットが停止しています'
end
bot.heartbeat do |_event|
  now = Date.today
  if previous < now
    save
    puts 'セーブしています'
    previous = now
  end
end
bot.ready do |event|
  bot.game = "#{DEFAULT_PREFIX}help"
end
bot.command(:start) do |event|
  channel = event.user.voice_channel
  if channel.nil? == true
    event.respond('ボイスチャット入ろうね!!');
  end
  if channel.nil? == false
    bot.voice_connect(channel)
    yomiage_start(event.server.id)
    event.channel.send_embed do |embed|
      embed.title = event.server.bot.name
      embed.description = "
読み上げを開始します
読み上げチャンネル #{channel.name}
使い方は#{get_prefix(event.message.server.id)}helpを参考にしてください
"
    end
  end
end
bot.command(:help) do |event|
  event.channel.embed do |embed|

  end
end



bot.command(:getvoice) do |event|
  if user_data_exists?(event.user.id)
    user = get_user_data(event.user.id)
    event.channel.send_embed do |embed|
      embed.title = "#{event.user.name}さんのボイス設定"
      embed.description = <<EOL
voice: #{user.voice}
emotion: #{user.emotion}
speed: #{user.speed}
tone: #{user.tone}
EOL
    end
  else
    register_user_data(event.user.id)
    event.respond('ユーザーデータ存在しなかったけど登録しといたよ')
  end
end

def emotion_included?(voice, emotion)
  voiceemotion = { 'mei' => ['angry', 'bashful', 'happy', 'normal', 'sad'], 'takumi' => ['normal', 'angry', 'sad', 'happy'],
                   'slt' => ['normal'] }
  voiceemotion[voice]&.include?(emotion)
end

bot.command(:setvoice) do |event, voice, emotion, speed, tone|
  error_messages = []

  unless VOICES.include?(voice)
    voice = nil
    error_messages << "対応していないvoiceです\n対応しているvoiceは#{get_prefix(event.server.id)}voicelistを参考にしてください"
  end
  unless emotion_included?(voice, emotion)
    emotion = nil
    error_messages << "対応していないemotionです\n対応しているemotionは#{get_prefix(event.server.id)}emotionlistを参考にしてください"
  end
  unless float?(speed)
    speed = nil
    error_messages << 'speedは数値にしてね'
  end
  unless float?(tone)
    tone = nil
    error_messages << 'toneは数値にしてね'
  end

  messages = error_messages.join("\n")

  if update_user_data(event.user.id, voice, emotion, speed, tone)
    event.respond("設定を保存しました\n" + ((size = error_messages.size) > 0 ?
                                     "ただし、#{size.to_s}件の設定は保存できませんでした:\n" + messages : ''))
  else
    event.respond('設定を保存できませんでした')
  end
end
bot.command(:eval, help_available: false) do |event, *code|

  if EVAL == 'true'
    break unless event.user.id == OWNER_ID # Replace number with your ID
    begin
      event.respond eval code.join(' ')
    rescue
      "エラーが発生しました。
      実行したコード：#{code.join(' ')}"
    end
  else
    event.respond("許可されていません\nconfig.envのEVALをtrueに変更してください")
  end
end
bot.command(:emotionlist) do |event|
  event.channel.send_embed do |embed|
    embed.title = '感情リスト'
    embed.description = "
    mei [angry,bashful,happy,normal,sad]\ntakumi [normal,angry,sad,happy]
"
  end
end
bot.command(:voicelist) do |event|
  event.channel.send_embed do |embed|
    embed.title = 'ボイスリスト'
    embed.description = "
    mei\ntakumi
"
  end
end

bot.message(contains: '') do |event|
  if yomiage_exists?(event.server.id) == true
    if user_data_exists?(event.user.id) == true
      if event.user.voice_channel.nil? == false
        yomiage_suru(event, event.content, event.voice, event.user.id, event.server.id)
      else
        register_user_data(event.user.id)
      end
    end
  end
end

bot.command(:volume) do |event, vol|
  if float?(vol)
    if vol.to_f <= 150 && vol.to_f >= 0
      voice_bot = event.voice
      voice_bot.filter_volume = vol
      event.respond("ボリュームを#{voice_bot.filter_volume}にしました")
    else
      event.respond('ボリュームを0から150の間で入力してください')
    end
  else

    event.respond('数字を入力してね')
  end
end

bot.command(:stop) do |event|
  if event.user.voice_channel.nil? == true
    event.respond('ボイスチャット入っていません')
  else
    event.voice.destroy
    yomiage_end(event.server.id)
    event.channel.send_embed do |embed|
      embed.title = event.server.bot.name
      embed.description = "
読み上げを終了してします
使い方は#{get_prefix(event.message.server.id)}helpを参考にしてください
"
    end
  end
end
bot.command(:setprefix) do |event, pre|
  if event.author.permission?('administrator') == true
    return 'prefixが入力されてないよ' if pre.nil?
    if pre.size <= 2
      if (set_prefix_result = set_prefix(pre, event.server.id)).instance_of?(Array)
        event.respond("prefixの設定中にエラーが発生しました:\n" + set_prefix_result.join("\n"))
      else
        event.respond("#{event.server.name}のprefixを#{pre}に変更しました")
      end
    else
      event.respond('prefixを二文字以内にしてください')
    end
  else
    event.respond('サーバーの管理者しか実行できません')
  end
end
bot.command(:botstop) do |event|
  if event.user.id == OWNER_ID
    save
    event.respond('ボットを停止中です')
    event.bot.stop
  else
    event.respond('このボットのオーナーじゃないためボットを停止することができません')
  end
end

bot.command(:botinfo) do |event|
  event.channel.send_embed do |embed|
    embed.title = 'ボットの詳細'
    embed.description = "
SERVERS
#{bot.servers.size}
USERS
#{bot.users.size}
PREFIX
#{get_prefix(event.server.id)}
招待リンク(開発中なので導入することをおすすめしません)
#{event.bot.invite_url}
開発者
#{bot.user(341902175120785419).username}##{bot.user(341902175120785419).discrim},#{bot.user(443427652951474177).username}##{bot.user(443427652951474177).discrim}
ホスト者
#{bot.user(OWNER_ID).username}##{bot.user(OWNER_ID).discrim}
"
  end
end
bot.run
