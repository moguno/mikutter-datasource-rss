#coding: utf-8


# IDからシンボルを作る
def sym(base, id)
  "#{base}_#{id}".to_sym
end

 
Plugin.create(:mikutter_datasource_rss) {
  require File.join(File.dirname(__FILE__), "rss_fetcher.rb")
  require File.join(File.dirname(__FILE__), "looper.rb")
  require "rubygems"
  require 'sanitize'


  ICON_COLORS = {
    :red => ["レッド", File.dirname(__FILE__) + "/red-icon-128.png"],
    :blue => ["ブルー", File.dirname(__FILE__) + "/blue-icon-128.png"],
    :black => ["ブラック", File.dirname(__FILE__) + "/black-icon-128.png"],
    :bronze => ["ブロンズ", File.dirname(__FILE__) + "/bronze-icon-128.png"],
    :green => ["グリーン", File.dirname(__FILE__) + "/green-icon-128.png"],
    :lightblue => ["ライトブルー", File.dirname(__FILE__) + "/lightblue-icon-128.png"],
    :mistred => ["ミストレッド", File.dirname(__FILE__) + "/mistred-icon-128.png"],
    :purple => ["パープル", File.dirname(__FILE__) + "/purple-icon-128.png"],
    :mikutter => ["みくったーちゃん", MUI::Skin.get("icon.png")],
  }


  class FetchLooper < MikutterDatasourceRSS::Looper
    def initialize(id)
      super()
      @id = id

      @user = User.new(:id => -3939, :idname => "RSS")
    end


    # フィードをメッセージに変換する
    def create_message(id, feed, entry)
      begin
        feed_title = feed.title.force_encoding("utf-8") 
        entry_title = entry.title.force_encoding("utf-8") 
        description = Sanitize.clean(entry.description)

        msg = Message.new(:message => ("【" + feed_title + "】\n" + entry_title + "\n\n" + description + "\n\n[記事を読む]"), :system => true)

        msg[:rss_feed_url] = entry.url.force_encoding("utf-8")
        msg[:created] = entry.last_updated
        msg[:modified] = Time.now


        # ユーザ
        image_url = if feed.image.empty?
          ICON_COLORS[UserConfig[sym("datasource_rss_icon", id)]][1]
        else
          feed.image
        end

        @user[:name] = feed_title
        @user[:profile_image_url] = image_url

        msg[:user] = @user

        msg
      rescue => e
        puts e.to_s
        puts e.backtrace
      end
    end


    def timer_set
      notice("#{@id} Timer set #{UserConfig[sym("datasource_rss_period", @id)]}")
      UserConfig[sym("datasource_rss_period", @id)]
    end


    def proc
      begin
        notice("#{@id} proc start")

        # パラメータ変更確認
        args = [
          "datasource_rss_url",
          "datasource_rss_loop",
          "datasource_rss_drop_day",
          "datasource_rss_reverse",
        ].map { |_|
          UserConfig[sym(_, @id)]
        }

        # パラメータが変わっていた場合、取得オブジェクトを再生成
        if !args[0].empty? && (@prev_args != args)
          notice("#{@id} proc reload")

          @prev_args = args

          @fetcher = RSSFetcher.new(*args, lambda { |*args| create_message(@id, *args) })
          @load_counter = 0
        end


        if @fetcher
          # データ取得
          msg = @fetcher.fetch


          # エントリーあり
          if msg
            notice("#{@id} send to datasource")
            msgs = Messages.new
            msgs << msg

            Plugin.call(:extract_receive_message, "rss/#{@id}".to_sym, msgs)
            Plugin.call(:extract_receive_message, :rss, msgs)
          end

          # RSSロードカウンタ満了
          @load_counter = if @load_counter <= 0
            notice("#{@id} RSS get")

            # RSSを読み込む
            @fetcher.load_rss 

            UserConfig[sym("datasource_rss_load_period", @id)] / UserConfig[sym("datasource_rss_period", @id)]
          else
            @load_counter - 1
          end
        end
      rescue => e
        puts e.to_s
        puts e.backtrace
      end
    end
  end


  # データソース登録
  filter_extract_datasources { |datasources|
    begin
      datasources[:rss] = "すべてのRSSフィード"

      10.times { |i|
        id = i + 1
        datasources["rss/#{id}".to_sym] = "RSSフィード#{id}"
      }

      [datasources]
    rescue => e
      puts e.to_s
      puts e.backtrace
    end
  }


  # 起動時
  on_boot { |service|
    begin
      10.times { |i|
        id = i + 1

        UserConfig[sym("datasource_rss_period", id)] ||= 1 * 60
        UserConfig[sym("datasource_rss_load_period", id)] ||= 1 * 60
        UserConfig[sym("datasource_rss_url", id)] ||= ""
        UserConfig[sym("datasource_rss_loop", id)] ||= false
        UserConfig[sym("datasource_rss_drop_day", id)] ||= 30
        UserConfig[sym("datasource_rss_reverse", id)] ||= false
        UserConfig[sym("datasource_rss_icon", id)] ||= 0
      }


      10.times { |i|
        id = i + 1

        FetchLooper.new(id).start
      }
    rescue => e
      puts e.to_s
      puts e.backtrace
    end
  }


  # 設定
  settings("RSS") {
    begin
      10.times { |i|
        id = i + 1

        settings("フィード#{id}") {
          input("URL", sym("datasource_rss_url", id))

          select("アイコンの色", sym("datasource_rss_icon", id), ICON_COLORS.inject({}){ |result, kv|
            result[kv[0]] = kv[1][0]
            result
          })

          adjustment("RSS取得間隔（秒）", sym("datasource_rss_load_period", id), 1, 600)
          adjustment("メッセージ出力間隔（秒）", sym("datasource_rss_period", id), 1, 600)
          adjustment("一定期間より前のフィードは流さない（日）", sym("datasource_rss_drop_day", id), 1, 365)
          boolean("新しい記事を優先する", sym("datasource_rss_reverse", id))
          boolean("ループさせる", sym("datasource_rss_loop", id))
        }
      }
    rescue => e
      puts e.to_s
      puts e.backtrace
    end 
  }


  # リンクの処理
  Message::Entity.addlinkrule(:rss, /\[記事を読む\]/) { |segment|
    if segment[:message][:rss_feed_url]
      Gtk::TimeLine.openurl(segment[:message][:rss_feed_url])
    end
  }
}
