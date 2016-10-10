#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
A simple script for bi-directional synchronization of BitBucket-hosted 
repositories with local mirrors. 

Given a ButBucket account name it synchronizes all repositories within that 
account to local ones. If local repository does not exist it is automatically 
created. A local repository is treated as a mirror of BitBucket one if basename
of the local directory matches "repo_slug" of the BitBucket repository. 

A regexp can be given to explicitly include or exclude repositories. Excludes are
applied after includes. If no includes are given, defaults to all repositories.
Patterns are matched against 'repo_slug'.

## Examples

To pull changes from all public repositories starting with 'stx-' or 'jv-' or
'ctu-' but not repository 'stx-goodies-builder-rake', jv-knowledge' or
 'jv-scripts' from https://bitbucket.org/janvrany to a current directory:

bitbucket-sync.rb --user janvrany --pull \\
                  --include '^stx-|^jv-|^ctu-' \\
                  --exclude 'stx-goodies-builder-rake|jv-knowledgebase|jv-scripts'

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'logger'
require 'tempfile'
require 'open3'

require 'net/http'
require 'json'

include FileUtils

if not $LOGGER then
  $LOGGER = Logger.new(STDOUT)
  $LOGGER.level = Logger::INFO  
end

$:.push(File.dirname($0))
require 'hglib'

module Net
  class HTTP
    def self.get_json(uri, user=nil, pass=nil) 
      if uri.is_a? String then
        uri = URI(uri)
      end
      req = Net::HTTP::Get.new(uri)
      if pass != nil then
        if user == nil then
          raise Exception.new("Password given but not username! Use user: named param to specify username.")
        end
        req.basic_auth(user, pass)      
      end      
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
        http.request(req)
      }
      data = res.body    
      return JSON.parse(data)
    end
  end
end

module BitBucket
  API_2_0_BASE_URL = "https://api.bitbucket.org/2.0"
  API_2_0_REPOSITORIES_URL = API_2_0_BASE_URL + '/repositories'

  class Account
    attr_accessor :name, :pass

    def initialize(name, pass = nil) 
      @name = name
      @pass = pass
    end

    def repositories()
      if @repositories == nil then        
        data = BitBucket::get_json(API_2_0_REPOSITORIES_URL + '/' + @name, @name, @pass)        
        @repositories = data.collect { | d | Repository.new(@name, @pass, d) }
      end
      return @repositories
    end
  end

  class Repository
    attr_accessor :user, :pass

    def initialize(user, pass, data) 
      @user = user
      @pass = pass
      @data = data
    end

    def name
      return @data['name']
    end

    def description
      return @data['name']
    end

    def hg?
      return @data['scm'] == 'hg'
    end

    def public?
      return ! @data['is_private']
    end

    def private?
      return ! self.public?
    end

    def pull_url(prefer_ssh = false)
      urls = @data['links']['clone']
      if prefer_ssh 
        urls.each { | url | return url['href'] if url['name'] == 'ssh' }
      end
      urls.each { | url | return url['href'] if url['name'] == 'https' }
      urls.each { | url | return url['href'] }
      return nil
    end

    def push_url(prefer_ssh = true)
      urls = @data['links']['clone']
      if prefer_ssh 
        urls.each { | url | return url['href'] if url['name'] == 'ssh' }
      end
      urls.each { | url | return url['href'] if url['name'] == 'https' }
      urls.each { | url | return url['href'] }
      return nil
    end

    def slug
      return @data['full_name'].split('/')[1]
    end

  end

  def self.get_json(uri, user = nil, pass = nil)    
    data = []
    while uri != nil do
      part = Net::HTTP::get_json(uri, user, pass)
      if part.has_key? 'page' and part.has_key? 'pagelen' and part.has_key? 'values' then
        # Paginated result, see
        # 
        #    https://confluence.atlassian.com/bitbucket/version-2-423626329.html#Version2-Pagingthroughobjectcollections 
        #
        data = data + part['values']      
        uri = part['next'] || nil
      else
        data = part;
        uri = nil
      end
    end
    return data
  end
end

module JV
  module Scripts
    class BitBucket_sync
      def sync(remote)
        prefer_ssh = @options[:ssh] || false
        pull_url = remote.pull_url(prefer_ssh)
        push_url = remote.push_url()
        local = @map[pull_url] || nil
        if not local then
          root = @options[:root] || '.'
          repo_path = File.join(root, remote.slug)
          if not HG::repository? repo_path            
            local = HG::Repository::init(repo_path)
            File.open(local.hgrc(), "a") do | f |
              f.write "[paths]\n"
              f.write "default = #{pull_url}\n"
              f.write "default-push = #{push_url}\n"
              f.write "\n"
              f.write "[web]\n"
              f.write "description = #{remote.description}\n"
              f.write "contact = #{local.config['ui']['username']}\n"
            end
          else
            local = HG::Repository.new(repo_path)
          end
          @map[pull_url] = local
        end
        sync0(remote, local)        
      end

      def sync0(remote, local)
        action = @options[:action] || :pullpush
        prefer_ssh = @options[:ssh] || false
        pull_url = remote.pull_url(prefer_ssh)
        push_url = remote.push_url()
        user = remote.user
        pass = remote.pass

        if @options[:dryrun] || false then
          puts "#{action} remote: #{pull_url} local: #{local.path}"
        elsif action == :incoming then
          sys "hg --cwd #{local.path} incoming #{pull_url}"
        elsif action == :pull then
          local.pull(pull_url, user: user, pass: pass)
        elsif action == :outgoing then
          sys "hg --cwd #{local.path} outgoing #{push_url}"
        elsif action == :push then
          local.push(push_url, user: user, pass: pass)
        elsif action == :pullpush then
          local.pull(pull_url, user: user, pass: pass)
          local.push(push_url, user: user, pass: pass)
        else
          $LOGGER.error("Unknown action '#{action}'")
          exit 1
        end
      end

      def run(*args, options)            
        @options = options
        @map = {}
        user = @options[:user] || nil
        pass = @options[:pass] || nil
        priv = @options[:private] || false
        inclpat = @options[:include] || nil        
        exclpat = @options[:exclude] || nil        
        if user == nil then
          $LOGGER.error("No user specified (use --user USER)")
          exit 1
        end
        account = BitBucket::Account.new(user, pass)
        account.repositories.each do | repo |                  
          if (repo.hg?) and
             (priv or repo.public?) and
             (inclpat == nil or (inclpat =~ repo.slug) != nil) and
             (exclpat == nil or (exclpat =~ repo.slug) == nil) 
          then
            sync(repo)
          end
        end
      end    
    end # class BitBucket_sync
  end # module JV::Scripts    
end # module JV

def run!() 
  opts = {}
  optparser = OptionParser.new do | optparser |
    optparser.banner = "Usage: $0 [--cwd REPOSITORY] [options]"
    optparser.on('-C', '--cwd ROOT', "ROOT directory containing sync'd repositories") do | value |
      opts[:root] = value
    end

    optparser.on('-u', '--user USER', "Sync repositories of USER") do | value |
      opts[:user] = value
    end

    optparser.on('-p', '--pass PASS', "UNSECURE! Use given PASS for HTTP authentication") do | value |
      opts[:pass] = value
    end

    optparser.on(nil, '--private', "Synchronize also private repositories") do
      opts[:private] = true
    end

    optparser.on('-i', '--include REGEXP', "Synchronize only repositories whose name matches REGEXP") do | value |      
      opts[:include] = Regexp.new(value)
    end    

    optparser.on('-e', '--exclude REGEXP', "DO NOT synchronize repositories whose name matches REGEXP") do | value |      
      opts[:exclude] = Regexp.new(value)
    end    

    optparser.on(nil, '--incoming', "Only show changes at BitBucket not in local mirror") do
      opts[:action] = :incoming
    end

    optparser.on(nil, '--ssh', "Prefer ssh:// protocol to pull from repository (default is to prefer https://") do | value |
      opts[:ssh] = true
    end

    optparser.on(nil, '--pull', "Only pull changes from BitBucket to local mirror") do
      opts[:action] = :pull
    end

    optparser.on(nil, '--outgoing', "Only show changes in local mirror not at BitBucket") do
      opts[:action] = :outgoing
    end

    optparser.on(nil, '--push', "Only push changes from local mirror to BitBucket") do
      opts[:action] = :push
    end

    optparser.on(nil, '--dry-run', "Process as normal but do not actually push or pull changes. Implies --verbose") do
      opts[:dryrun] = true
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
    end

    optparser.on(nil, '--verbose', "Print more information during processing") do
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
    end

    optparser.on(nil, '--debug', "Print debug messages during processing") do
      $LOGGER.level = Logger::DEBUG
      begin
        require 'pry'
        require 'pry-byebug'
      rescue LoadError => ex
        $LOGGER.info "Gems pry and/or pry-byebug not installed, no interactive debugging available"
        $LOGGER.info "Run 'gem install pry pry-byebug' to install."
      end      
    end

    optparser.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparser.help()
      exit 0
    end
  end
  optparser.parse! 

  JV::Scripts::BitBucket_sync.new().run(ARGV, opts)
end

run! if __FILE__ == $0
