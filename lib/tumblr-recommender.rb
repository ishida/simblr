# coding: utf-8
require 'tumblr_client'
require 'yaml'
require 'set'
require 'thread'

class TumblrRecommender
  DEFAULT_LIMIT = 20

  def initialize(attrs = {})
    @client = Tumblr::Client.new attrs
  end

  def request_and_retry(request, success_cond, error_cond = nil, max = 3,
    sleep_seconds = 1)
    if error_cond == nil
      error_cond = proc do |res|
        !res.nil? && !res['status'].nil? && res['status'] >= 400
      end
    end
    res = nil
    max.times do |i|
      res = request.call
      break if success_cond.call(res) || error_cond.call(res)
      sleep(sleep_seconds)
    end
    res
  end

  def job_to_get_posts(host, offset, limit, notes_info, reblog_info, responds,
    lock)
    proc do
      res = request_and_retry(
        proc {
          begin
            @client.posts(host, :offset => offset, :limit => limit,
              :notes_info => notes_info, :reblog_info => reblog_info)
          rescue => ex
            { error: ex }
          end
        },
        proc { |res| !res.nil? && !res['blog'].nil? &&
          !res['blog']['posts'].nil? && !res['posts'].nil?
        })
      lock.synchronize { responds << res }
    end
  end

  def jobs_to_get_posts(host, max_posts, notes_info, reblog_info, responds,
    lock)
    offset = 0
    limit = DEFAULT_LIMIT
    jobs = []
    while offset < max_posts
      limit = max_posts - offset if (max_posts - offset < limit)
      jobs << job_to_get_posts(host, offset, limit, notes_info, reblog_info,
        responds, lock)
      offset += limit
    end
    jobs
  end

  # NOTE: You may fail to get a little posts when you add and get posts at once.
  def get_posts(host, max_posts = 20, notes_info = false, reblog_info = false)
    res = []
    job_to_get_posts(host, 0, 1, false, false, res, Mutex.new).call
    return nil if res.size <= 0 || res[0].nil?
    return res[0] if res[0]['blog'].nil? ||
      res[0]['blog']['name'].nil? || res[0]['blog']['posts'].nil?

    blog_name = res[0]['blog']['name']
    max_posts = [res[0]['blog']['posts'], max_posts].min
    res = []
    jobs = jobs_to_get_posts(host, max_posts, notes_info, reblog_info, res,
      Mutex.new)
    ThreadPool.new(jobs).execute
    posts = {}

    res.each do |v|
      if !v.nil? && !v['posts'].nil?
        v['posts'].each { |pt| posts[pt['id']] = pt }
      end
    end

    { host: host, blog_name: blog_name, posts: posts.values }
  end

  def get_tentative_following(posts_cont)
    posts = posts_cont[:posts]
    blogs = {}
    posts.each do |post|
      next unless post.key?('reblogged_from_name')
      b = post['reblogged_from_name']
      h = post['reblogged_from_url'].scan(/http:\/\/([^\/]+)\//)[0][0]
      blogs[b] = h
    end
    blogs
  end

  def get_top_blogs(posts_cont, blogs_max = 10, deselected_blogs = {})
    posts = posts_cont[:posts]
    host = posts_cont[:host]
    blog_name = posts_cont[:blog_name]
    top_blogs_hash = {}
    deselected_blogs = {} if deselected_blogs.nil?

    posts.each do |post|
      next unless post.key?('notes')

      tmp_hash = {}
      if post.key?('reblogged_root_name') && post.key?('reblogged_root_url')
        b = post['reblogged_root_name']
        h = post['reblogged_root_url'].scan(/http:\/\/([^\/]+)\//)[0][0]
        tmp_hash[b] = { count: 1, host: h } unless b == blog_name
      end

      post['notes'].each do |n|
        next unless n.key?('blog_name') && n.key?('type') && n.key?('blog_url')
        b = n['blog_name']
        t = n['type']
        h = n['blog_url'].scan(/http:\/\/([^\/]+)\//)[0][0]
        next if t == 'like' || h == host
        tmp_hash[b] = { count: 1, host: h }
      end

      tmp_hash.each_pair do |b, v|
        c = top_blogs_hash.key?(b) ? top_blogs_hash[b][:count] + 1 : 1
        top_blogs_hash[b] = { count: c, host: v[:host] }
      end
    end

    posts_size = posts.size.to_f
    t = top_blogs_hash.sort { |a, b|
      (b[1][:count] <=> a[1][:count]) * 2 + (a[0] <=> b[0]) }
    blogs_count = 0
    top_blogs = []
    t.each do |v|
      break if blogs_count >= blogs_max
      next if deselected_blogs.key?(v[0])

      top_blogs << {
        blog_name: v[0],
        sim: v[1][:count].to_f / posts_size,
        host: v[1][:host] }

      blogs_count += 1
    end

    top_blogs
  end

  def get_top_posts(top_blogs, max_posts_a_blog, deselected_blog_names = [],
    deselected_urls = [])
    deselected_blog_names = [] if deselected_blog_names.nil?
    deselected_urls = [] if deselected_urls.nil?
    top_blogs_h = top_blogs.inject({}) { |r, v|
      r[v[:blog_name]] = { sim: v[:sim], host: v[:host] }; r }

    res = []
    lock = Mutex.new
    jobs = top_blogs.inject([]) { |r, v|
      r += jobs_to_get_posts(v[:host], max_posts_a_blog, true, true, res, lock); r }
    ThreadPool.new(jobs).execute
    posts = res.inject([]) { |r, v|
      r += v['posts'] if !v.nil? && !v['posts'].nil?; r }

    url_post_conts = {}
    posts.each do |post|
      has_reblogged_root = false
      if post['reblogged_root_url'].nil? || post['reblogged_root_name'].nil?
        url = post['post_url'].slice(/^http[s]?:\/\/[^\/]+\/post\/[^\/]+/)
        url = post['post_url'] if url.nil? || url == ''
        root_blog_name = post['blog_name']
      else
        has_reblogged_root = true
        url = post['reblogged_root_url']
        root_blog_name = post['reblogged_root_name']
      end
      next if url.nil? || deselected_urls.include?(url)
      next if !root_blog_name.nil? && deselected_blog_names.include?(root_blog_name)

      post_cont = url_post_conts.key?(url) ? url_post_conts[url] : {}
      blogs = post_cont.key?(:blogs) ? post_cont[:blogs] : Set.new
      blogs.add(post['blog_name'])

      unless post['notes'].nil?
        post['notes'].each do |note|
          u = note['blog_name']
          t = note['type']
          next if t == 'like' || deselected_blog_names.include?(u) || !top_blogs_h.key?(u)
          blogs.add(u)
        end
      end
      blogs.add(root_blog_name) unless has_reblogged_root
      post_cont[:post] = post unless post_cont.key?(:post)
      post_cont[:blogs] = blogs
      url_post_conts[url] = post_cont
    end

    sim_sum = top_blogs_h.values.inject(0.0) { |r, v| r + v[:sim] }
    url_post_conts.each_value do |post_cont|
      blogs = post_cont[:blogs]
      sim_pref_sum = post_cont[:blogs].inject(0.0) do |r, u|
        r + top_blogs_h[u][:sim]
      end
      post_cont[:score] = sim_pref_sum / sim_sum
    end

    t = url_post_conts.sort { |a, b| b[1][:score] <=> a[1][:score] }
    t.map do |v|
      { url: v[0], score: v[1][:score], post: v[1][:post], blogs: v[1][:blogs] }
    end
  end

  def get_recommendation(host, max_posts_a_top_blog = 10, max_top_blogs = 10)
    is_success = true
    top_posts = nil
    top_blogs = nil
    msg = nil
    error = nil
    posts_cont = get_posts(host, 100, true, true)

    if posts_cont.nil? || posts_cont[:blog_name].nil? || posts_cont[:host].nil?
      msg = posts_cont.nil? || posts_cont['msg'].nil? ? nil : posts_cont['msg']
      is_success = false
      error = posts_cont[:error]
    else
      deselected_blogs = get_tentative_following(posts_cont)
      top_blogs = get_top_blogs(posts_cont, max_top_blogs, deselected_blogs)
      deselected_blog_name = posts_cont[:blog_name]
      deselected_urls = posts_cont[:posts].inject({}) { |r, v|
        r[v['reblogged_root_url']] = true unless v['reblogged_root_url'].nil?; r }.keys
      posts_cont = nil
      top_posts = get_top_posts(top_blogs, max_posts_a_top_blog, [deselected_blog_name], deselected_urls)

      if top_blogs.nil? || top_blogs.size <= 0 || top_posts.nil? || top_posts.size <= 0
        msg = 'Not Enough Reblog Info'
        is_success = false
      end
    end

    { success: is_success,
      msg: msg,
      error: error,
      top_posts: top_posts,
      top_blogs: top_blogs }
  end
end

class TumblrRecommender::ThreadPool
  def initialize(procs, size = 10)
    @jobs = procs.inject(Queue.new) { |r, v| r.push(v); r }
    @size = size
  end

  def execute
    @size.times.map do
      Thread.start do
        until @jobs.empty?
          j = @jobs.pop(true) rescue break
          j.call
          sleep(0.000001)
        end
      end
    end.each { |t| t.join rescue next }
  end
end
