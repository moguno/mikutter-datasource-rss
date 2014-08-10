#coding: utf-8

class RSSFetcher
  require 'rubygems'
  require 'feed-normalizer'
  require "date"
  require "open-uri"


  # コンストラクタ
  def initialize(url, loop, drop_day, reverse, on_create_message)
    @on_create_message = on_create_message
    @result_queue = []
    @queue_lock = Mutex.new
    @last_fetch_time = Time.now
    @last_load_time = nil

    @url = url
    @loop = loop
    @drop_day = drop_day
    @reverse = reverse
  end


  # 保有データを1つ取り出す
  def fetch
    begin
      msg = @queue_lock.synchronize {
        if @reverse
          @result_queue.pop
        else
          @result_queue.shift
        end
      }

      if msg
        @last_fetch_time = Time.now
        msg[:modified] = Time.now
      end

      msg
    rescue => e
      puts e.to_s
      puts e.backtrace
    end
  end


  # データ保有してる？
  def empty?()
    @result_queue.empty?
  end


  # RSSを取得する
  def load_rss()
    begin
      # URLなし->終了
      if !@url || @url.empty?
        return true
      end


      # メッセージが無くなったらループさせる
      if @loop && empty?
        @last_load_time = nil
      end


      # RSSを読み込む
      feed = open(@url) { |fp|
        FeedNormalizer::FeedNormalizer.parse(fp)
      }


      # フィードの選別 
      # フィードを捨てる期間を計算する
      drop_time = Time.now.to_i - (24 * 60 * 60 * @drop_day)

      entries = feed.entries.select { |entry|
        begin
          # 古すぎる -> 捨てる
          if entry.last_updated != nil && entry.last_updated.to_i < drop_time then
            false

          # 初取得 -> 採用
          elsif @last_load_time == nil then
            true

          # 前回ロード時以降に発生した -> 採用
          elsif entry.last_updated != nil && @last_load_time < entry.last_updated then
            true

          # その他 -> 捨てる
          else
            false
          end
        rescue => e
          puts e.to_s
          puts s.backtrace
          false
        end
      }

      # 採用なし
      if entries.size == 0
        return true
      end


      # エントリをメッセージに変換する
      msgs = entries.map { |entry|
        @on_create_message.call(feed, entry)
      }


      # メッセージをキューに投入
      @queue_lock.synchronize {
        @result_queue.concat(msgs.reverse)
      }


      # 最新のエントリーの時刻を記録する
      last_entry_time = entries.select { |_| _.last_updated }.max_by { |a, b|
        (a <=> b)
      }.last_updated

      if last_entry_time
        @last_load_time = last_entry_time
      end
 
      true

    rescue => e
      puts e.to_s
      puts e.backtrace

      false 
    end
  end
end
