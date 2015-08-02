#coding: utf-8

module MikutterDatasourceRSS
  # ループする
  class Looper
    def initialize
      @stop = false
    end

    def start
      proc
      interval = timer_set

      if !interval
        @stop = true
        return
      end

      Reserver.new(interval) { start }
    end

    def stop?
      @stop
    end
  end
end
