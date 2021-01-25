require 'discordrb'
require 'json'
require 'dotenv'
require 'sqlite3'
require './db/connect'
require './models/user'
require './models/prefix'
require './models/dictionary'
require './models/emoji'
Dotenv.load 'config.env'

# dotenvで必要な値を定義する
DOTENV_REQUIRED = ['TOKEN', 'OWNER_ID', 'DEFAULT_PREFIX', 'EVAL'].freeze

error_count = 0
DOTENV_REQUIRED.each do |required|
  if ENV[required].nil?
    error_count += 1
    puts "config.envに#{required}が無いよ"
  end
end
if error_count.positive?
  puts 'config_sample.envを参考にconfig.envを編集してください'
  exit
end

DEBUG_ACTIVERECORD_LOG = (ENV["DEBUG_ACTIVERECORD_LOG"] || false) == 'true'
DEBUG_SEND_YOMIAGE = (ENV["DEBUG_SEND_YOMIAGE"] || false) == 'true'
DEBUG_DISABLE_TALK = (ENV["DEBUG_DISABLE_TALK"] || false) == 'true'

ALPHABET_EMOJIS = ('🇦'..'🇿').to_a

DATA = 'data'.freeze
PREFIXDATA = DATA + '\prefix.json'.freeze
MIGRATED_PREFIXDATA = DATA + '\migrated_prefix.json'.freeze
OPEN_JTALK = 'open_jtalk\bin\open_jtalk.exe'.freeze
VOICE = ' -m open_jtalk\bin\Voice'.freeze
DIC = ' -x open_jtalk\bin\dic'.freeze
INPUT = 'open_jtalk\bin\input'.freeze
OUTPUT = 'open_jtalk\bin\output'.freeze
OWNER_ID = ENV['OWNER_ID'].to_i.freeze
DEFAULT_PREFIX = ENV['DEFAULT_PREFIX'].freeze
EVAL = ENV['EVAL'].freeze
$yomiage = []
$yomiagenow = [] # キュー消化中のリスト
ActiveRecord::Base.logger = Logger.new(STDOUT) if DEBUG_ACTIVERECORD_LOG

$queue = Hash.new { |h, k| h[k] = [] }
$yomiage_target_channel = Hash.new { |h, k| h[k] = [] }

# User.id => Message
$select_voice_reaction_waiting = {}
# User.id => voice
$select_voice_cache = {}
# User.id => Message
$select_emotion_reaction_waiting = {}

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

# 絵文字DB
if Emoji.count < 1
  add_count = 0

  emojis = JSON.load(File.new("./resources/emoji_ja.json"))
  emojis.each do |character, meta|
    Emoji.create(character: character, read: meta["short_name"])
    add_count += 1
  end

  puts add_count.to_s + "個の絵文字を登録しました"
end

def available_voices
  Dir.glob("./open_jtalk/bin/Voice/*").map do |file|
    next unless FileTest.directory?(file)
    File.basename(file)
  end.compact
end

def available_emotions(voice)
  Dir.glob("./open_jtalk/bin/Voice/#{voice}/*.htsvoice").map do |file|
    next if FileTest.directory?(file)
    File.basename(file).chomp('.htsvoice')
  end.compact
end

def add_jisyo(serverid, before, after)
  Dictionary.create(serverid: serverid, before: before, after: after)
end

def remove_jisyo(serverid, before)
  if (dict = Dictionary.find_by(serverid: serverid, before: before)).nil?
    return false
  end
  dict.destroy
end

def get_jisyo_all(serverid)
  Dictionary.where(serverid: serverid)
end

# 辞書の通り置換する
def jisyo_replace(serverid, message)
  # TODO: MySQLでは結合にconcatを使うけど..。
  dictionaries = Dictionary.where(serverid: serverid).where('? LIKE "%"||before||"%"', message).order('length(before) DESC')
  dictionaries.each { |dictionary| message.gsub!(dictionary.before, dictionary.after) }
  emojis = Emoji.where('? LIKE "%"||character||"%"', message)
  emojis.each { |emoji| message.gsub!(emoji.character, emoji.read) }
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

def replace_url_to_s(text, s = 'url省略')
  #regexp = URI::DEFAULT_PARSER.make_regexp(%w(http, https))
  regexp = URI::DEFAULT_PARSER.make_regexp
  text.to_enum(:scan, regexp).map { Regexp.last_match }.each { |match| text.gsub!(match[0], s) }
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
  replace_url_to_s(msg)
  $queue[serverid].push(msg)
  unless $yomiagenow.include?(serverid) # キュー消化中でなかったら
    $yomiagenow.push(serverid)
    loop do
      if yomiage_exists?(serverid)
        text = $queue[serverid].shift
        jisyo_replace(serverid, text)
        event.respond '読み上げ: ' + text if DEBUG_SEND_YOMIAGE
        begin
          yomiage(event, text, voice, userid, serverid) unless DEBUG_DISABLE_TALK
        rescue Exception => e
          event.respond("読み上げ中にエラーが発生したよ: " + e.message)
        end
      end
      if $queue[serverid].size.zero? or !(yomiage_exists?(serverid))
        $yomiagenow.delete(serverid)
        break
      end
    end
  end
end

def yomiage(event, msg, voice, userid, serverid)
  File.write("open_jtalk\\bin\\input\\v#{event.server.id}.txt", msg, encoding: Encoding::SJIS)
  user = get_user_data(userid)
  s = system(cmd = OPEN_JTALK + VOICE + '\\' + "#{user.voice}" + '\\' + "#{user.emotion}" + '.htsvoice' + DIC + ' -fm ' + "#{user.tone}" + ' -r ' + "#{user.speed}" + ' -ow ' + OUTPUT + '\v' + "#{serverid}.wav" + ' ' + INPUT + '\v' + "#{serverid}.txt")
  if s == true
    #voice_bot = event.voice
    voice.play_file(OUTPUT + '\v' + "#{serverid}" + '.wav')
  else
    event.respond('コマンド実行エラー')
    p cmd
  end
end

bot = Discordrb::Commands::CommandBot.new(token: ENV['TOKEN'], prefix: prefix_proc)

bot.ready do |event|
  bot.game = "#{DEFAULT_PREFIX}help"
end

bot.command(
  :start,
  description: '読み上げを開始する',
  aliases: [:s]
) do |event|
  channel = event.user.voice_channel
  return 'ボイスチャット入ろうね!!' if channel.nil? == true
  return 'このチャンネルはすでに読み上げ対象です' if $yomiage_target_channel[event.server.id].include?(event.channel.id)
  name = []
  bot.voice_connect(channel)
  yomiage_start(event.server.id)
  $yomiage_target_channel[event.server.id].push(event.channel.id)
  $yomiage_target_channel[event.server.id].each do |id|
    name.push("<##{id}>")
  end
  name = name.join(",")
  event.channel.send_embed do |embed|
    embed.title = event.server.bot.name
    embed.description = <<EOL
読み上げを開始します
読み上げ対象チャンネル#{name}
読み上げが終了してからbotがボイスチャットに残った場合や読み上げがされない場合は、#{get_prefix(event.message.server.id)}stopコマンドで強制終了してね
使い方は#{get_prefix(event.message.server.id)}helpを参考にしてください
EOL
  end
end

bot.command(
  :getvoice,
  description: 'ボイス設定を表示する',
  aliases: [:gv]
) do |event|
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

bot.command(
  :setspeedtone,
  description: '速さと高さを設定する',
  usage: 'setspeedtone <速さ> <高さ>',
  arg_types: [Float, Float],
  min_args: 2,
  aliases: [:sst]
) do |event, speed, tone|
  if speed.nil?
    return 'speedは数値にしてね'
  end
  if tone.nil?
    return 'toneは数値にしてね'
  end

  if update_user_data(event.user.id, nil, nil, speed, tone)
    event.respond("設定を保存しました")
  else
    event.respond('設定を保存できませんでした')
  end
end

bot.command(
  :setvoiceemotion,
  description: '声質と感情を設定する',
  aliases: [:sve]
) do |event|
  i = -1
  message = event.channel.send_embed do |embed|
    embed.title = '声質選択'
    embed.description = "声質を選んでね\n" +
      available_voices.map { |voice| i += 1; "#{ALPHABET_EMOJIS[i]} #{voice}" }.join("\n")
  end
  available_voices.size.times { |j| message.create_reaction(ALPHABET_EMOJIS[j]) }
  $select_voice_reaction_waiting.store(event.user.id, message)
  nil # 神言語なので必要
end

bot.reaction_add do |event|
  if $select_voice_reaction_waiting.keys.include?(event.user.id) and event.message === (message = $select_voice_reaction_waiting[event.user.id])
    next if (select_index = ALPHABET_EMOJIS.index(event.emoji.to_reaction)).nil?
    next if (select_voice = available_voices[select_index]).nil?
    $select_voice_reaction_waiting.delete(event.user.id)
    message.delete
    i = -1
    message = event.channel.send_embed do |embed|
      embed.title = "感情選択 [#{select_voice}]"
      embed.description = "感情を選んでね\n" +
        available_emotions(select_voice).map { |emotion| i += 1; "#{ALPHABET_EMOJIS[i]} #{emotion}" }.join("\n")
    end
    $select_voice_cache[event.user.id] = select_voice
    available_emotions(select_voice).size.times { |j| message.create_reaction(ALPHABET_EMOJIS[j]) }
    $select_emotion_reaction_waiting.store(event.user.id, message)
  end
  if $select_emotion_reaction_waiting.keys.include?(event.user.id) and event.message === (message = $select_emotion_reaction_waiting[event.user.id])
    select_voice = $select_voice_cache[event.user.id]
    $select_voice_cache.delete(event.user.id)
    next if (select_index = ALPHABET_EMOJIS.index(event.emoji.to_reaction)).nil?
    next if (select_emotion = available_emotions(select_voice)[select_index]).nil?
    $select_emotion_reaction_waiting.delete(event.user.id)
    message.delete
    if update_user_data(event.user.id, select_voice, select_emotion)
      event.respond("設定を保存しました")
    else
      event.respond('設定を保存できませんでした')
    end
  end
end

bot.command(
  :eval,
  help_available: false,
  description: 'コードを評価する',
  usage: 'eval <コード>'
) do |event, *code|
  break unless event.user.id == OWNER_ID # Replace number with your ID
  return "許可されていません\nconfig.envのEVALをtrueに変更してください" unless EVAL == 'true'
  begin
    event.respond eval code.join(' ')
  rescue
    "エラーが発生しました。
      実行したコード：#{code.join(' ')}"
  end
end

bot.command(
  :voicelist,
  description: 'ボイス/感情リストを表示する',
  aliases: [:emotionlist, :vl, :el]
) do |event|
  event.channel.send_embed do |embed|
    embed.title = 'ボイス/感情リスト'
    embed.description = available_voices.map { |voice| "#{voice} [#{available_emotions(voice).join(',')}]" }.join("\n")
  end
end

bot.command(
  :addword,
  description: '単語を追加する',
  usage: 'addword <単語> <読み>',
  arg_types: [String, String],
  min_args: 2,
  aliases: [:aw]
) do |event, before, after|
  return 'サーバーの管理者しか実行できません' unless event.author.permission?('administrator') == true
  add_jisyo(event.server.id, before, after)
  event.respond('辞書に追加しました')
end

bot.command(
  :removeword,
  description: '単語を削除する',
  usage: 'removeword <単語>',
  arg_types: [String],
  min_args: 1,
  aliases: [:rw]
) do |event, before|
  return 'サーバーの管理者しか実行できません' unless event.author.permission?('administrator') == true
  if remove_jisyo(event.server.id, before) === false
    event.respond('存在しません')
  else
    event.respond("`#{before}`を辞書から削除しました")
  end
end

bot.command(
  :wordlist,
  description: '単語リストを表示する',
  aliases: [:wl]
) do |event|
  words_list_string = ""
  get_jisyo_all(event.server.id).each do |dictionary|
    words_list_string += "\n#{dictionary.before} => #{dictionary.after}"
  end
  event.channel.send_embed do |embed|
    embed.title = 'ワードリスト'
    embed.description = words_list_string
  end
end

bot.message do |event|
  next if event.user.bot_account
  next unless yomiage_exists?(event.server.id) == true
  if user_data_exists?(event.user.id) == true
    next unless $yomiage_target_channel[event.server.id].include?(event.channel.id) == true
    next if event.content.start_with?(";")
    yomiage_suru(event, event.content, event.voice, event.user.id, event.server.id)
  else
    register_user_data(event.user.id)
    event.respond('ユーザーデータ存在しなかったけど登録しといたよ')
  end
end

bot.voice_state_update do |event|
  if event.channel.nil?
    # VCの参加者がこのbotだけになった場合に読み上げを終了する
    if event.old_channel.users.size == 1 and event.old_channel.users[0].current_bot?
      $yomiage_target_channel[event.server.id].each do |id|
        channel = event.bot.channel(id, event.server.id)
        embed = Discordrb::Webhooks::Embed.new(title: event.server.bot.name)
        embed.description = "人がいなくなったため\n読み上げを終了しています\n使い方は#{get_prefix(event.server.id)}helpを参考にしてください"
        event.bot.send_message(channel, "", false, embed)
      end
      event.bot.voices[event.server.id].destroy
      yomiage_end(event.server.id)
      $yomiage_target_channel.delete(event.server.id)
    end
    # 読み上げを終了していないのにVCから切断された場合読み上げを終了する
    if yomiage_exists?(event.server.id) and !(event.old_channel.users.map { |user| user.id }.include?(event.server.bot.id))
      puts "読み上げを終了していないのにVCから切断されました"
      yomiage_end(event.server.id)
      $yomiage_target_channel.delete(event.server.id)
    end
  end
end

bot.command(
  :volume,
  description: '音量を設定する',
  usage: 'volume <音量>',
  arg_types: [Float],
  min_args: 1,
  aliases: [:vol]
) do |event, vol|
  return '先に読み上げを開始してください' if event.voice.nil?
  return '数字を入力してね' if vol.nil?
  if vol <= 150 && vol >= 0
    voice_bot = event.voice
    voice_bot.filter_volume = vol
    event.respond("ボリュームを#{voice_bot.filter_volume}にしました")
  else
    event.respond('ボリュームを0から150の間で入力してください')
  end
end

bot.command(
  :stop,
  description: '読み上げを終了する',
  aliases: [:end, :e]
) do |event|
  if yomiage_exists?(event.server.id) == true
    event.voice.destroy
    yomiage_end(event.server.id)
    $yomiage_target_channel.delete(event.server.id)
    event.channel.send_embed do |embed|
      embed.title = event.server.bot.name
      embed.description = <<EOL
読み上げを終了してします
読み上げが終了してからbotがボイスチャットに残った場合や読み上げがされない場合は、#{get_prefix(event.message.server.id)}stopコマンドで強制終了してね
使い方は#{get_prefix(event.message.server.id)}helpを参考にしてください
EOL
    end
  else
    # 強制終了
    return 'ボイスチャンネルが一つもないよ' if event.server.voice_channels.size <= 0
    stopping_message = event.channel.send_embed do |embed|
      embed.title = event.server.bot.name
      embed.description = <<EOL
読み上げを強制終了しています
強制終了中にサーバー内のボイスチャンネルに接続する場合があります
EOL
    end
    bot.voice_connect(event.server.voice_channels[0]) # 一旦接続しないとできない
    event.voice.destroy
    yomiage_end(event.server.id)
    $yomiage_target_channel.delete(event.server.id)
    event.channel.send_embed do |embed|
      embed.title = event.server.bot.name
      embed.description = <<EOL
読み上げを強制終了しました
使い方は#{get_prefix(event.message.server.id)}helpを参考にしてください
EOL
    end
    stopping_message.delete
  end
end

bot.command(
  :setprefix,
  description: 'プレフィックスを設定する',
  usage: 'setprefix <プレフィックス>',
  arg_types: [String],
  min_args: 1,
  aliases: [:sp]
) do |event, pre|
  return 'サーバーの管理者しか実行できません' unless event.author.permission?('administrator') == true
  return 'prefixが不正だよ' if pre.nil?
  return 'prefixを1文字以上10文字以内にしてください' unless pre.size >= 1 and pre.size <= 10
  if (set_prefix_result = set_prefix(pre, event.server.id)).instance_of?(Array)
    event.respond("prefixの設定中にエラーが発生しました:\n" + set_prefix_result.join("\n"))
  else
    event.respond("#{event.server.name}のprefixを#{pre}に変更しました")
  end
end

bot.command(
  :botstop,
  description: 'ボットを停止する',
  aliases: [:bs]
) do |event|
  return 'このボットのオーナーじゃないためボットを停止することができません' unless event.user.id == OWNER_ID
  event.respond('ボットを停止中です')
  event.bot.stop
end

bot.command(
  :botinfo,
  description: 'ボットの詳細を表示する',
  aliases: [:bi]
) do |event|
  event.channel.send_embed do |embed|
    embed.title = 'ボットの詳細'
    embed.description = <<EOL
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
EOL
  end
end
bot.run
