require 'headhunter'
require 'spec'
require 'rack/test'

set :environment, :test

describe "Headhunter" do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    # ugly hack to suppress warnings about 'already initialized constant CACHE'
    class Object ; remove_const :CACHE if const_defined?(:CACHE) ; end
  end

  it "should not respond to /favicon.ico" do
    get '/favicon.ico'
    last_response.should be_not_found
  end

  describe "Homepage" do

    it "should respond" do
      get '/'
      last_response.should be_ok
    end

    it "should show the remaining hits allowed by the Twitter API" do
      Net::HTTP.should_receive(:get).and_return({
        :reset_time_in_seconds => "1269200600",
        :remaining_hits => "123",
        :hourly_limit => "150"
      }.to_json)
      Time.should_receive(:now).any_number_of_times.and_return(
        now = mock('now', :to_i => 1269200000).as_null_object)
      get '/'
      last_response.body.should =~ /123/
      last_response.body.should =~ /reset to 150/
      last_response.body.should =~ /10[^0-9]+minutes/
    end

  end

  describe "serving user avatars" do

    before do
      CACHE = mock('Memcached').as_null_object
    end

    describe 'having requested avatar in cache' do

      before do
        CACHE.stub!(:get).with('awendt').and_return("cached_avatar_url")
        @mock_http = mock('http')
        @mock_head_response = mock('response')
        Net::HTTP.should_receive(:new).and_return(@mock_http)
        @mock_http.stub!(:request_head).and_return(@mock_head_response)
      end

      it "should check the cached avatar with a HEAD request" do
        @mock_head_response.should_receive(:code).and_return('200')
        @mock_http.should_receive(:request_head).with('cached_avatar_url').and_return(
          @mock_head_response)

        get '/awendt'
      end

      it "should redirect" do
        @mock_head_response.should_receive(:code).and_return('200')
        get '/awendt'

        last_response.should be_redirect
        last_response.headers['Location'].should == 'cached_avatar_url'
      end

      describe "but it expired" do

        before do
          @mock_head_response.should_receive(:code).and_return('404')
          Net::HTTP.stub!(:get).and_return({:profile_image_url => 'avatar_url'}.to_json)
        end

        it "should fetch the avatar" do
          Net::HTTP.should_receive(:get).and_return({:profile_image_url => 'avatar_url'}.to_json)

          get '/awendt'
        end

        it "should not verify the new URL" do
          @mock_http.should_not_receive(:request_head).with('avatar_url')

          get '/awendt'
        end

        it "should redirect to the new URL" do
          get '/awendt'

          last_response.should be_redirect
          last_response.headers['Location'].should == 'avatar_url'
        end

      end

    end

    describe 'without having requested avatar cached' do

      before do
        CACHE.stub!(:get).with('awendt').and_raise(Memcached::NotFound)
        Net::HTTP.stub!(:get).and_return({:profile_image_url => 'avatar_url'}.to_json)
      end

      it "should fetch avatar from Twitter" do
        Net::HTTP.should_receive(:get).and_return({:profile_image_url => 'avatar_url'}.to_json)

        get '/awendt'
      end

      it "should cache the avatar" do
        CACHE.should_receive(:set).with('awendt', 'avatar_url')

        get '/awendt'
      end

      it "should redirect" do
        get '/awendt'

        last_response.should be_redirect
        last_response.headers['Location'].should == 'avatar_url'
      end
    end
  end
end
