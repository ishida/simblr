# coding: utf-8
require_relative 'spec_helper'
require_relative '../app'

def should_redirect_to(loc)
  expect(last_response).to be_redirect
  expect(last_response.location).to eq('http://example.org' << loc)
end

describe App do

  include Rack::Test::Methods
  def app
    @app ||= App
  end

  describe 'GET', '/' do
    context 'without querys' do
      before { get '/' }
      subject(:res) { last_response }

      it 'responds ok' do
        expect(res).to be_ok, "Actual status: #{res.status}"
      end

      it 'shows a top page' do
        expect(res.body).to include('<!-- index -->')
      end
    end

    context 'with valid querys' do
      context '/?q=example.com' do
        before { get '/?q=example.com' }
        subject(:res) { last_response }

        it 'responds ok' do
          expect(res).to be_ok, "Actual status: #{res.status}"
        end

        it 'shows a result page' do
          expect(res.body).to include('<!-- result -->')
        end
      end

      context '/?q=http://example.com/foo' do
        it "redirects to '/?q=example.com'" do
          get '/?q=http://example.com/foo'
          should_redirect_to '/?q=example.com'
        end
      end

      context '/?q=example' do
        it "redirects to '/?q=example.tumblr.com'" do
          get '/?q=example'
          should_redirect_to '/?q=example.tumblr.com'
        end
      end
    end

    context 'with invalid querys' do
      context '/?q=' do
        it "redirects to '/'" do
          get '/?q='
          should_redirect_to('/')
        end
      end
    end
  end

  describe 'GET', '/close' do
    before { get '/close' }
    subject(:res) { last_response }

    it 'responds ok' do
      expect(res).to be_ok, "Actual status: #{res.status}"
    end

    it 'shows a closing page' do
      expect(res.body).to include('<!-- close -->')
    end
  end

  describe 'GET', 'not-found location' do
    before { get '/foo' }
    subject(:res) { last_response }

    it 'responds not-found' do
      expect(res).to be_not_found, "Actual status: #{res.status}"
    end
  end

  describe 'GET', '/result' do
    context 'with valid blog' do
      context '/result/test-normal.tumblr.com' do
        let(:path) { '/result/test-normal.tumblr.com' }

        it 'responds ok' do
          get path
          res = last_response
          expect(res).to be_ok, "Actual status: #{res.status}"
        end

        it 'shows a waiting result of page fragments at the first response' do
          get path
          expect(last_response.body).to include('<!-- result_waiting -->')
        end

        it 'shows a success result of page fragments after finishing background job' do
          get path
          30.times do
            break unless last_response.body.include?('<!-- result_waiting -->')
            sleep(1)
            get path
          end
          expect(last_response.body).to include('<!-- result_success -->')
        end
      end
    end

    context 'with invalid blog' do
      context '/result/not-found-not-found-not-found.tumblr.com' do
        let(:path) { '/result/not-found-not-found-not-found.tumblr.com' }

        it 'responds ok' do
          get path
          res = last_response
          expect(res).to be_ok, "Actual status: #{res.status}"
        end

        it 'shows a waiting result of page fragments at the first response' do
          get path
          expect(last_response.body).to include('<!-- result_waiting -->')
        end

        it 'shows an error result of page fragments after finishing background job' do
          get path
          30.times do
            break unless last_response.body.include?('<!-- result_waiting -->')
            sleep(1)
            get path
          end
          expect(last_response.body).to include('<!-- result_error -->')
        end

        it "shows 'Not Found'" do
          get path
          expect(last_response.body).to include('Not Found')
        end
      end

      context '/result/invalid_host_name' do
        let(:path) { '/result/invalid_host_name' }

        it 'responds ok' do
          get path
          res = last_response
          expect(res).to be_ok, "Actual status: #{res.status}"
        end

        it "shows 'Not Found'" do
          get path
          expect(last_response.body).to include('Not Found')
        end
      end

      context '/result/test-no-posts.tumblr.com' do
        let(:path) { '/result/test-no-posts.tumblr.com' }

        it 'responds ok' do
          get path
          res = last_response
          expect(res).to be_ok, "Actual status: #{res.status}"
        end

        it 'shows a waiting result of page fragments at the first response' do
          get path
          expect(last_response.body).to include('<!-- result_waiting -->')
        end

        it 'shows an error result of page fragments after finishing background job' do
          get path
          30.times do
            break unless last_response.body.include?('<!-- result_waiting -->')
            sleep(1)
            get path
          end
          expect(last_response.body).to include('<!-- result_error -->')
        end

        it "shows 'Not Enough Reblog Info'" do
          get path
          expect(last_response.body).to include('Not Enough Reblog Info')
        end
      end
    end
  end

end
