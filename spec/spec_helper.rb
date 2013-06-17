# coding: utf-8
require 'rubygems'
require 'sinatra'
require 'rack/test'
require 'rspec'
require_relative '../app'

set :environment, :test
set :run, false
set :raise_errors, true
set :logging, false

def should_redirect_to(loc)
  expect(last_response).to be_redirect
  expect(last_response.location).to eq('http://example.org' << loc)
end
