# coding: utf-8
require 'sinatra/base'
require 'sinatra/reloader'
require 'haml'
require 'yaml'
require 'sanitize'
require 'dalli'
require 'memcachier'
require_relative 'lib/tumblr-recommender'

class App < Sinatra::Base
  @@worker_lock = Mutex.new
  @@working_queries = {}
  @@restarting_lock = Mutex.new
  @@is_restarting = false

  configure do
    require 'newrelic_rpm' if production?
    require 'heroku-api' if production?
    register Sinatra::Reloader if development?
    use Rack::Deflater

    set :haml, { :format => :html5 }
    set :worker_max, (ENV['WORKER_MAX'] || 10).to_i
    set :memory_kbyte_max, (ENV['MEMORY_KBYTE_MAX'] || 480000).to_i
    set :tr_max_posts_a_top_blog, (ENV['TR_MAX_POSTS_A_TOP_BLOG'] || 10).to_i
    set :tr_max_top_blogs, (ENV['TR_MAX_TOP_BLOGS'] || 10).to_i
    set :tumblr_consumer_key, (ENV['TUMBLR_CONSUMER_KEY'] ||
      open(File.dirname(__FILE__) + '/.tumblr') { |f|
        YAML.load(f) }['consumer_key'])
    set :heroku_app_name, (ENV['HEROKU_APP_NAME'] || 'simblr')
    cache_sec = (ENV['DEFAULT_CACHE_MAX_AGE_SEC'] || 86400).to_i
    set :cache_max_age_sec, cache_sec
    set :static_cache_control, [:public, :max_age => cache_sec]
  end

  configure :test do
    enable :raise_errors
    disable :run, :logging
    @@dc_test = {}
  end

  configure :test, :development do
    set :cache_max_age_sec, 0
    set :static_cache_control, 0
  end

  configure :development, :production do
    enable :logging
    set :dc, Dalli::Client.new(nil, :compress => true,
      :expires_in => (ENV['MEMCACHED_EXPIRES_IN_SEC'] || 60).to_i)
    set :memory_dc, Dalli::Client.new(nil,
      :expires_in => (ENV['MEM_MEMCACHED_EXPIRES_IN_SEC'] || 5).to_i)
  end

  before do
    cache_control :public, :max_age => settings.cache_max_age_sec

    @app_name = 'Simblr'
    @host_name = request.host
    @host_name_enc = request.host
    if !production? && request.port != 80
      @host_name << ":#{request.port}"
      @host_name_enc << "%3a#{request.port}"
    end
  end

  after '/result/:q' do
    @top_posts = nil
    @top_blogs = nil
    @top_blogs_h = nil
    GC.start
  end

  get '/' do
    q = params[:q]

    if production?
      @newrelic_header = ::NewRelic::Agent.browser_timing_header rescue ''
      @newrelic_footer = ::NewRelic::Agent.browser_timing_footer rescue ''
    else
      @newrelic_header = @newrelic_footer = ''
    end

    return haml :index if q.nil?

    tq = q.dup
    if tq =~ /^[a-zA-Z0-9-]+$/
      tq = tq + '.tumblr.com'
    elsif tq =~ /^http[s]?:\/\//
      tq = tq.sub(/^http[s]?:\/\//, '').sub(/\/.*/, '')
    end
    tq = '' unless tq =~ /^(?:[a-zA-Z0-9][a-zA-Z0-9-]*[.])*(?:[a-zA-Z0-9][a-zA-Z0-9-]+)$/
    tq = tq[0..255] if tq.size > 255

    redirect '/', 303 if tq == ''
    redirect '/?q=' + tq, 303 if tq != q

    @q = q
    haml :result
  end

  get '/result/:q' do |q|
    cache_control :public, :max_age => 0

    if q.size <= 255 && q =~ /^(?:[a-zA-Z0-9][a-zA-Z0-9-]*[.])*(?:[a-zA-Z0-9][a-zA-Z0-9-]+)$/
      @q = q
    else
      @q = nil
      @error_msg = 'Not Found'
    end

    status = :failed
    logger_msg = nil

    unless @q.nil?
      result_cont, has_worker_available, has_memory_available, mem, is_waiting =
        request_result(q)
      if is_waiting
        status = :waiting
      elsif result_cont.nil?
        status = :failed
        @error_msg = 'Server too busy. Please try again later. ['
        logger_msg = 'Server too busy.'
        unless has_worker_available
          @error_msg << 'W'
          logger_msg << " Too many workers(#{settings.worker_max})."
        end
        unless has_memory_available
          @error_msg << 'M'
          logger_msg <<  "Too high memory usage(#{mem} > #{settings.memory_kbyte_max}[KB])."
        end
        @error_msg << ']'
      else
        result = result_cont[:result]
        status = result[:success] ? :success : :failed
        if status == :success
          @top_posts = result[:top_posts]
          @top_blogs = result[:top_blogs]
          @top_blogs_h = @top_blogs.inject({}) { |r, v|
            r[v[:blog_name]] = { sim: v[:sim], host: v[:host] }; r }
          @elapsed_time = result_cont[:elapsed_time]
        else
          @error_msg = result[:msg] unless result[:msg].nil? || result[:msg] == ''
          error = result[:error]
        end

        unless error.nil?
          logger_msg = error.to_s << ": " <<
            error.backtrace[0...10].inject('') { |r, v| r << "\n" << v } << "\n..."
        end
      end
    end

    case status
    when :success
      haml :result_success, :layout => false
    when :waiting
      haml :result_waiting, :layout => false
    else
      logger.warn(logger_msg) unless logger_msg.nil?
      @error_msg = 'Please try again later.' if @error_msg.nil? || @error_msg == ''
      haml :result_error, :layout => false
    end
  end

  get '/close' do
    haml :close, :layout => false
  end

  helpers do
    def production?
      settings.production?
    end

    def development?
      settings.development?
    end

    def test?
      settings.test?
    end

    def logger
      request.logger
    end

    def s(html)
      Sanitize.clean(html,
        :elements => %w{br p a img blockquote},
        :attributes => {
          'a' => ['href'],
          'img' => ['alt', 'height', 'src', 'width'] })
    end

    def prepare_post(post_cont)
      post = post_cont[:post]
      score = (post_cont[:score]*100).round
      blog_ids = post_cont[:blogs].map { |b| "blog_#{b}" }.join(',')
      post_id = "post_#{post['id']}"
      [post, score, blog_ids, post_id]
    end

    def prepare_photoset(post)
      caption = post['caption']
      photos = post['photos']
      photoset_layout = post['photoset_layout']
      photoset_layout = photos.inject('') { |r, _| r << '1' } if photoset_layout.nil?

      photoset = []
      base_w = 500
      photo_idx = 0
      photoset_layout.length.times do |i|
        n = photoset_layout[i].to_i
        width = (base_w - (n - 1) * 10) / n
        photos_row = []
        n.times do |j|
          photo = photos[photo_idx]
          url = ''
          tmp_w = 0
          tmp_h = 0
          sub_caption = photo['caption']
          alt_sizes = photo['alt_sizes'].sort { |a, b| a['width'] <=> b['width'] }
          alt_sizes.each do |alt|
            url = alt['url']
            tmp_w = alt['width']
            tmp_h = alt['height']
            break if tmp_w >= width
          end
          big_url = alt_sizes[alt_sizes.size - 1]['url']
          height = tmp_h * width / tmp_w
          photos_row << {
            url: url,
            big_url: big_url,
            sub_caption: sub_caption,
            width: width,
            height: height }
          photo_idx += 1
        end

        min_h = 100000000
        photos_row.each { |photo| min_h = photo[:height] if photo[:height] < min_h }
        photos_row.each { |photo| photo[:margin_top] = min_h - photo[:height] }
        photoset << { photos_row: photos_row, height: min_h }
      end

      photoset
    end

    def prepare_video(post)
      player_alts = post['player'].sort { |a, b| a['width'] <=> b['width'] }
      embed_code = ''
      player_alts.each do |alt|
        break if alt['width'] > 510
        embed_code = alt['embed_code']
      end
      embed_code
    end

    def memory_usage
      return 0 if test?
      mem = settings.memory_dc.get('memory')
      if mem.nil?
        mem = `ps -o rss= -p #{Process.pid}`.to_i
        settings.memory_dc.set('memory', mem)
      end
      mem
    end

    def restart(msg)
      unless production?
        logger.warn('Restarting acutially only in production env')
        return
      end
      @@restarting_lock.synchronize do
        return if @@is_restarting
        @@is_restarting = true
      end
      logger.warn(msg)
      Heroku::API.new.post_ps_restart(settings.heroku_app_name)
    end

    def request_result(q)
      result_cont = nil
      mem = memory_usage
      has_memory_available = (mem <= settings.memory_kbyte_max)
      has_worker_available = false
      works = false
      is_waiting = false

      @@worker_lock.synchronize do
        has_worker_available = (@@working_queries.size < settings.worker_max)
        if test?
          result_cont = @@dc_test[q]
        else
          result_cont = settings.dc.get(q)
        end
        if result_cont.nil? && has_worker_available && has_memory_available && @@working_queries[q].nil?
          @@working_queries[q] = true
          works = true
        end
        is_waiting = !@@working_queries[q].nil?
      end

      if works
        Thread.start(q) do |query|
          time_start = Time.now
          result_cont = {
            result: TumblrRecommender.new({ consumer_key:
              settings.tumblr_consumer_key }).get_recommendation(query,
              settings.tr_max_posts_a_top_blog, settings.tr_max_top_blogs),
            elapsed_time: sprintf('%.4f', (Time.now - time_start)) }
          logger.info("TumblrRecommender: \"#{query}\" #{result_cont[:elapsed_time]}")

          @@worker_lock.synchronize do
            if test?
              @@dc_test[query] = result_cont
            else
              settings.dc.set(query, result_cont)
            end
            @@working_queries.delete_if { |k, _| k == query }
          end

          result_cont = nil
          GC.start
          if memory_usage > settings.memory_kbyte_max
            restart("Restarting because of too high memory usage...")
          end
        end
      end

      [result_cont, has_worker_available, has_memory_available, mem, is_waiting]
    end
  end
end
