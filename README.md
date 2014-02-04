# Simblr [![Build Status](https://travis-ci.org/ishida/simblr.png?branch=master)](https://travis-ci.org/ishida/simblr) [![Coverage Status](https://coveralls.io/repos/ishida/simblr/badge.png?branch=master)](https://coveralls.io/r/ishida/simblr?branch=master)

[Simblr](http://simblr.i4da.com/) is a web application which recommends [Tumblr](http://tumblr.com/) blogs and posts for you by reference to your recent Tumblr posts.

Recommending Tumblr posts using algorithms of collaborative filtering and others.  
Using Ruby, Sinatra, Puma, Memcached, Heroku, jQuery, AJAX, Bootstrap, Tumblr API and others.

You can try [the demo](http://simblr.i4da.com/).

## Supported Ruby

* 2.0.0
* 1.9.3
* 1.9.2

## Installation

Install:

    $ git clone https://github.com/ishida/simblr.git simblr
    $ cd simblr
    $ gem install bundler
    $ bundle install --path vendor/bundle

Get [Tumblr API consumer key](http://www.tumblr.com/docs/en/api/v2).

### Development environment

Create a file including Tumblr API consumer key (and replace such strings as "aaa" to real ones):

    $ echo 'consumer_key: "aaa"' > .tumblr

Install memcached in some way and run:

    $ memcached

And run a development server with:

    $ bundle exec puma

Check "http://127.0.0.1:9292/" with a browser.

### Production environment

Create [Heroku account](https://heroku.com/) and install [Heroku Toolbelt](https://toolbelt.heroku.com/) in advance.  
Install the others:

    $ heroku create --stack cedar bbb
    $ heroku addons:add memcachier
    $ heroku addons:add newrelic
    $ heroku config:add BUNDLE_WITHOUT=development:test
    $ heroku config:set TUMBLR_CONSUMER_KEY=aaa
    $ heroku config:set HEROKU_API_KEY=ccc
    $ heroku config:set HEROKU_APP_NAME=ddd

Options:

    $ heroku addons:add papertrail
    $ heroku config:set MEMORY_KBYTE_MAX=480000
    $ heroku config:set WORKER_MAX=10
    $ heroku config:set MEMCACHED_EXPIRES_IN_SEC=60
    $ heroku config:set DEFAULT_CACHE_MAX_AGE_SEC=2592000
    $ heroku config:set TZ=Asia/Tokyo
    $ heroku config:set TR_MAX_POSTS_A_TOP_BLOG=10
    $ heroku config:set TR_MAX_TOP_BLOGS=10

Server has already started. Check "http://bbb.herokuapp.com/" with a browser.

## Testing

Setup the development environment and execute:

    $ bundle exec rake

## TODO

* Move heavy threads in App#request_result to other worker processes if necessary.
* Improve a memory management.
