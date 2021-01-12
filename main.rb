# frozen_string_literal: true

# discordrb can send music or other audio data to voice channels. This example exists to show that off.
#
# To avoid copyright infringement, the example music I will be using is a self-composed piece of highly debatable
# quality. If you want something better you can replace the files in the data/ directory. Make sure to execute this
# example from the appropriate place, so that it has access to the files in that directory.

require 'discordrb'
require 'json'
require 'Date'
require 'Open3'
require 'dotenv'

PREFIXDATA = 'data\\prefix.json'
USERDATA = 'data\\user.json'

OWNER_ID = 341902175120785419
$yomiage = []
Dotenv.load
File.open(PREFIXDATA) do |prefixfile|
  $prefix = JSON.load(prefixfile)
end
PREFIXES = $prefix
File.open(USERDATA) do |user|
  $user = JSON.load(user)
  p $user
end

def set_prefix(pre, serverid)
  $prefix[serverid] = pre
end

prefix_proc = proc do |message|
  prefix = PREFIXES[message.server.id] || '#'
  message.content[prefix.size..-1] if message.content.start_with?(prefix)
end

def set_user_data(userid, emotions, voice, speed, thone)
  $user[userid]['Emotions'] = emotions
  $user[userid]['voice'] = voice
  $user[userid]['speed'] = speed
  $user[userid]['thone'] = thone
end
def get_user_data(userid)
  return $user[userid]
  end
def register_user_data(userid)
  $user[userid]["Emotions"] = 'nomarl'
  $user[userid]['voice'] = 'mei'
  $user[userid]['speed'] = 1
  $user[userid]['thone'] = 0
end

def user_data_is?(userid)
  user[userid].nil?
end

def yomiage_is?(serverid)
  $yomiage[serverid].nil?
end

def yomiage_start(serverid)
  $yomiage.push(serverid)
end
def yomiage_end(serverid)
  $yomiage.delete(serverid)
end
def save()
  File.open(PREFIXDATA, 'w') do |file|
    JSON.dump(PREFIXES, file)
  end
  File.open(USERDATA, 'w') do |userfile|
    JSON.dump($user,userfile)
  end
end

bot = Discordrb::Commands::CommandBot.new(token: ENV["TOKEN"], prefix: prefix_proc)

previous = Date.today
bot.disconnected do |event|
  save()
  puts "ボットが停止しています"
end
bot.heartbeat do |_event|
  now = Date.today
  if previous < now
    save()
    puts 'セーブしています'
    previous = now
  end
end
bot.command(:start) do |event|
  channel = event.user.voice_channel
  event.respond('ボイスチャット入ろうね!!') if channel.nil? == true
  bot.voice_connect(channel)
  yomiage_start(event.server.id)
  event.channel.send_embed do |embed|
    embed.title = "読み上げくんv2"
    embed.description = "
読み上げを開始します
読み上げチャンネル #{channel.name}
使い方は#{PREFIXES[event.message.server.id] || '#'}helpを参考にしてください
"
  end
end
bot.command(:help) do |event|
  event.channel.embed do |embed|

  end
end
bot.command(:play_mp3) do |event|
  voice_bot = event.voice
  voice_bot.play_file('data/music.mp3')
end
OPEN_JTALK = 'open_jtalk\bin\open_jtalk.exe'
VOICE = ' -m open_jtalk\bin\Voice'
VOICES = ["mei","takumi","salt"]
Emotions = ["normal","angry","sad","bashful","happy"]
NORMAL = '\normal.htsvoice'
ANGRY = '\angry.htsvoice'
SAD = '\sad.htsvoice'
BASHFUL = '\bashful.htsvoice'
HAPPY = '\happy.htsvoice'
DIC = ' -x open_jtalk\bin\dic'
INPUT = 'open_jtalk\bin\input'
OUTPUT = 'open_jtalk\bin\output'

bot.command(:yomiage) do |event,msg|
  File.write("open_jtalk\\bin\\input\\v#{event.server.id}.txt",msg, encoding: Encoding::SJIS)
  uservoice = get_user_data(event.user.id)
  s = system(OPEN_JTALK + VOICE + uservoice["voice"] + DIC + ' -fm ' + uservoice["thone"] + ' -r ' + uservoice["speed"] + ' -ow ' + OUTPUT + '\v' + event.server.id + INPUT + '\v' + event.server.id)
  if s == true
  voice_bot = event.voice
  voece_bot.play_file(OUTPUT + 'v' + event.server.id + '.wav')
  else
    event.respond("コマンド実行エラー")
  end
end

bot.command(:setvoice) do |event,voice,emotions,speed,thone|
  register_user_data(event.user.id)
end
bot.command(:eval, help_available: false) do |event, *code|
  break unless event.user.id == 341902175120785419 # Replace number with your ID

  begin

    event.respond eval code.join(' ')
  rescue
    "エラーが発生しました。
      実行したコード：#{code.join(' ')}"
  end
end
=begin
bot.message(contains: "") do |event|
  if yomiage_is?(event.server.id)

    if event.user.voice_channel.nil? == false
      if user_data_is?(event.user.id)

      else
        register_user_data(event.user.id)
      end
    end
  end
end
=end

bot.command(:volume) do |event, vol|
  if (/^[+-]?[0-9]*[\.]?[0-9]+$/ =~ vol)

    if vol.to_f <= 150 && vol.to_f >= 0
      voice_bot = event.voice
      voice_bot.filter_volume = vol
      event.respond("ボリュームを#{voice_bot.filter_volume}にしました")
    else
      event.respond("ボリュームを0から150の間で入力してください")
    end
  else

    event.respond('数字を入力してね')
  end
end

bot.command(:stop) do |event|
  event.respond('ボイスチャット入っていません') if channel.nil? == true
  event.voice.destroy
  yomiage_end(event.server.id)
  event.channel.send_embed do |embed|
    embed.title = "読み上げくんv2"
    embed.description = "
読み上げを終了してします
使い方は#{PREFIXES[event.message.server.id] || '#'}helpを参考にしてください
"
  end
end
bot.command(:setprefix) do |event, pre|
  if event.author.permission?("administrator") == true
    set_prefix(pre, event.server.id)
    event.respond("#{event.server.name}のprefixを#{pre}に変更しました")
  else
    event.respond('サーバーの管理者しか実行できません')
  end
end
bot.command(:botstop) do |event|
  if event.user.id == OWNER_ID
    save()
    event.respond('ボットを停止中です')
    event.bot.stop
  else
    event.respond('このボットのオーナーじゃないためデータをセーブすることができません')
  end
end

bot.command(:save) do |event|
  if event.user.id == OWNER_ID
    save()
      event.respond('セーブ中です')
  else
    event.respond('このボットのオーナーじゃないためデータをセーブすることができません')
  end
end
bot.command(:botinfo) do |event|
  event.channel.send_embed do |embed|
    embed.title = "ボットの詳細"
    embed.description = "
SERVERS
#{bot.servers.size}
USERS
#{bot.users.size}
PREFIX
#{PREFIXES[event.server.id] || '#'}
招待リンク(開発中なので導入することをおすすめしません)
#{event.bot.invite_url}
開発者
#{bot.user(341902175120785419).username}##{bot.user(341902175120785419).discrim}"
  end
end
bot.run
