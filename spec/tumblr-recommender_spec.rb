# coding: utf-8
require 'spec_helper'

describe TumblrRecommender do

  before(:all) do
    @normal_blog_name = 'test-normal'
    @normal_blog_host = @normal_blog_name + '.tumblr.com'
    @tentative_following_blog_name = 'test-tentative-following'
    @tentative_following_blog_host = @tentative_following_blog_name + '.tumblr.com'
    @recommended_blog_name = 'test-various-posts'
    @recommended_blog_host = @recommended_blog_name + '.tumblr.com'
    @no_posts_blog_name = 'test-no-posts'
    @no_posts_blog_host = @no_posts_blog_name + '.tumblr.com'
    @not_found_blog_name = 'not_found'
    @not_found_blog_host = @not_found_blog_name + '.tumblr.com'

    @valid_consumer_key = open(File.dirname(__FILE__) + '/../.tumblr') { |f|
      YAML.load(f) } ['consumer_key']
    @dummy_consumer_key = 'dummy'

    @req_posts_num = 40
    @posts_cont = TumblrRecommender.new( :consumer_key => @valid_consumer_key )
      .get_posts(@normal_blog_host, @req_posts_num, true, true)
  end

  let(:tr) { TumblrRecommender.new(consumer_key: consumer_key) }
  let(:consumer_key) { @valid_consumer_key }
  let(:posts_cont) { @posts_cont }
  let(:req_posts_num) { @req_posts_num }
  let(:blog_name) { @normal_blog_name }
  let(:blog_host) { blog_name + '.tumblr.com' }

  describe '#request_and_retry' do
    let(:consumer_key) { @dummy_consumer_key }

    it 'retries a job a specified number of times' do
      cnt = 0
      max = 5
      res = tr.request_and_retry(
        lambda { cnt += 1 }, lambda { |_| false }, lambda { |_| false },
        max, 0.1)
      expect(res).to eq(max)
    end

    it 'stops retrying when matched a success condition' do
      cnt = 0
      res = tr.request_and_retry(
        lambda { cnt += 1 }, lambda { |v| v >= 1 }, lambda { |_| false },
        3, 0.1)
      expect(res).to eq(1)
    end

    it 'stops retrying when matched an error condition' do
      cnt = 0
      res = tr.request_and_retry(
        lambda { cnt += 1 }, lambda { |_| false }, lambda { |v| v >= 1 },
        3, 0.1)
      expect(res).to eq(1)
    end
  end

  describe '#job_to_get_posts' do
    context 'with a valid consumer key' do
      context 'with a normal blog' do
        it 'returns a proc to get posts' do
          res = []
          tr.job_to_get_posts(blog_host, 0, 1, false, false, res, Mutex.new).call
          expect(res[0]['blog']['name']).to eq(blog_name)
        end
      end

      context 'with a no-posts blog' do
        let(:blog_name) { @no_posts_blog_name }

        it 'returns a proc to get an empty array as a posts value' do
          res = []
          tr.job_to_get_posts(blog_host, 0, 1, false, false, res, Mutex.new).call
          expect(res[0]['blog']['name']).to eq(blog_name)
          expect(res[0]['posts']).to eq([])
        end
      end

      context 'with a not-found blog' do
        let(:blog_name) { @not_found_blog_name }

        it 'returns a proc to get not-found result' do
          res = []
          tr.job_to_get_posts(blog_host, 0, 1, false, false, res, Mutex.new).call
          expect(res).to eq([{ 'status' => 404, 'msg' => 'Not Found' }])
        end
      end
    end

    context 'with an invalid consumer key' do
      let(:consumer_key) { @dummy_consumer_key }

      it 'returns a proc to get not-authorized result' do
        res = []
        tr.job_to_get_posts(blog_host, 0, 1, false, false, res, Mutex.new).call
        expect(res[0]).to eq({ 'status' => 401, 'msg' => 'Not Authorized' })
      end
    end
  end

  describe '#jobs_to_get_posts' do
    let(:res) { [] }
    let(:jobs) { tr.jobs_to_get_posts(blog_host, req_posts_num, false, false,
      res, Mutex.new) }

    it 'returns a proper size array of proc' do
      max_posts_num_a_req = 20 # Tumblr default
      expect(jobs.size).to eq((req_posts_num.to_f / max_posts_num_a_req).ceil)
    end

    it 'returns a proc array to get a specified number or less of posts' do
      TumblrRecommender::ThreadPool.new(jobs).execute
      posts = {}
      res.each do |r|
        if !r.nil? && !r['posts'].nil?
          r['posts'].each { |v| posts[v['id']] = v }
        end
      end
      real_posts_num = res[0]['blog']['posts']
      expect(posts.values.size).to eq([real_posts_num, req_posts_num].min)
    end
  end

  describe '#get_posts' do
    context 'with a valid consumer key' do
      context 'with a normal blog' do
        it 'returns a hash including keys of blog short name, host name and posts array' do
          expect(posts_cont.keys.sort).to eq([:blog_name, :host, :posts].sort)
        end

        it 'includes a proper blog short name' do
          expect(posts_cont[:blog_name]).to eq(blog_name)
        end

        it 'includes a proper blog host name' do
          expect(posts_cont[:host]).to eq(blog_host)
        end

        it 'includes a specified number or less of posts' do
          posts_num = tr.job_to_get_posts(blog_host, 0, 1, false, false, [],
            Mutex.new).call[0]['blog']['posts']
          expect(posts_cont[:posts].size).to eq(
            [req_posts_num, posts_num].min)
        end
      end

      context 'with a no-posts blog' do
        let(:blog_name) { @no_posts_blog_name }
        let(:posts_cont) { tr.get_posts(blog_host, 1, true, true) }

        it 'returns a hash including a empty array as a posts value' do
          expect(posts_cont[:posts]).to eq([])
        end
      end

      context 'with a not-found blog' do
        let(:blog_name) { @not_found_blog_name }
        let(:posts_cont) { tr.get_posts(blog_host, 1, true, true) }

        it 'returns a hash including a nil as a posts value' do
          expect(posts_cont[:posts]).to be_nil
        end
      end
    end

    context 'with an invalid consumer key' do
      let(:consumer_key) { @dummy_consumer_key }
      let(:posts_cont) { tr.get_posts(blog_host, 1, false, false) }

      it 'returns not-authorized message' do
        expect(posts_cont).to eq({ 'status' => 401, 'msg' => 'Not Authorized' })
      end
    end
  end

  describe '#get_tentative_following' do
    let(:consumer_key) { @dummy_consumer_key }

    it 'returns an array of blogs who recent posts are reblogged from' do
      expect(tr.get_tentative_following(posts_cont)).to eq({
        @tentative_following_blog_name => @tentative_following_blog_host})
    end
  end

  describe '#get_top_blogs' do
    let(:consumer_key) { @dummy_consumer_key }

    it 'returns an array of blog short name, host name and simularity' do
      top_blogs = tr.get_top_blogs(posts_cont, 10)
      expect(top_blogs[0].keys.sort).to eq([:blog_name, :sim, :host].sort)
    end

    it 'includes top recommended blogs' do
      deselected_blogs = tr.get_tentative_following(posts_cont)
      top_blogs = tr.get_top_blogs(posts_cont, 10, deselected_blogs)
      top_blogs_hosts = top_blogs.map { |e| e[:host] }
      expect(top_blogs_hosts).to include(@recommended_blog_host)
    end

    it 'returns a specified number or less of blogs' do
      num = 10
      top_blogs = tr.get_top_blogs(posts_cont, num)
      expect(top_blogs.size).to be <= num
    end

    it 'deselects specified blogs' do
      deselected_blogs = tr.get_tentative_following(posts_cont)
      deselected_blogs_hosts = deselected_blogs.values
      top_blogs = tr.get_top_blogs(posts_cont, 10)
      top_blogs_hosts = top_blogs.map { |e| e[:host] }
      deselected_blogs_hosts.each do |e|
        expect(top_blogs_hosts).to include(e)
      end

      top_blogs = tr.get_top_blogs(posts_cont, 10, deselected_blogs)
      top_blogs_hosts = top_blogs.map { |e| e[:host] }
      deselected_blogs_hosts.each do |e|
        expect(top_blogs_hosts).not_to include(e)
      end
    end
  end

  describe '#get_top_posts' do
    let(:top_blogs) { [{
        blog_name: @recommended_blog_name,
        sim: 100,
        host: @recommended_blog_host }] }
    let(:deselected_blog_names) { [@normal_blog_name] }
    let(:deselected_blog_urls) { @posts_cont[:posts].inject({}) { |r, v|
        r[v['reblogged_root_url']] = true unless v['reblogged_root_url'].nil?; r }.keys }

    it 'returns top recommended posts' do
      top_posts = tr.get_top_posts(top_blogs, 20)
      expect(top_posts[0].keys.sort).to eq([:url, :score, :post, :blogs].sort)
    end

    it 'returns a specified number or less of posts a blog' do
      max_posts_a_blog = 20
      real_posts_num = tr.job_to_get_posts(@recommended_blog_name, 0, 1, false,
        false, [], Mutex.new).call[0]['blog']['posts'] # => 15
      duplication_posts_num = 2 # the num is counted by actually checking blog_host and recommended_blog_host
      top_posts = tr.get_top_posts(top_blogs, max_posts_a_blog,
        deselected_blog_names, deselected_blog_urls)
      expect(top_posts.size).to eq(
        [max_posts_a_blog, real_posts_num].min - duplication_posts_num)
    end
  end

  describe '#get_recommendation' do
    context 'with a valid consumer key' do
      context 'with a normal blog' do
        it 'returns recommended posts, blogs, success flag, message and error' do
          expect(tr.get_recommendation(blog_host).keys.sort).to eq(
            [:success, :msg, :error, :top_posts, :top_blogs].sort)
        end
      end

      context 'with a no-posts blog' do
        let(:blog_name) { @no_posts_blog_name }

        it 'returns not-success flag and not-enough-reglog-info message' do
          expect(tr.get_recommendation(blog_host)).to eq({
            success: false,
            msg: "Not Enough Reblog Info",
            error: nil,
            top_posts: [],
            top_blogs: []})
        end
      end

      context 'with a not-found blog' do
        let(:blog_name) { @not_found_blog_name }

        it 'returns not-success flag and not-found message' do
          expect(tr.get_recommendation(blog_host)).to eq({
            success: false,
            msg: "Not Found",
            error: nil,
            top_posts: nil,
            top_blogs: nil})
        end
      end
    end

    context 'with an invalid consumer key' do
      let(:consumer_key) { @dummy_consumer_key }

      it 'returns not-success flag and not-authorized message' do
        expect(tr.get_recommendation(blog_host)).to eq({
          success: false,
          msg: "Not Authorized",
          error: nil,
          top_posts: nil,
          top_blogs: nil})
      end
    end
  end

end

describe TumblrRecommender::ThreadPool do

  let(:result) do
    res = {}
    lock = Mutex.new
    jobs = jobs_size.times.map do |i|
      lambda { lock.synchronize { res[i] = Thread.current.object_id } }
    end
    TumblrRecommender::ThreadPool.new(jobs, threads_size).execute
    res
  end
  let(:jobs_size) { 10000 }
  let(:threads_size) { 100 }

  it 'executes all jobs' do
    expect(result.keys.sort).to eq((0...jobs_size).to_a)
  end

  it 'executes jobs using a specified number of threads' do
    expect(result.values.uniq.size).to eq(threads_size)
  end

end
