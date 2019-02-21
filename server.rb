#!/usr/bin/env ruby

require "sinatra"
require "json"
require "git"
require "fileutils"
require "nokogiri"
require "mail"

if ENV.key? "FC_MAIL"
  Mail.defaults do
    delivery_method :smtp, address: ENV["FC_MAIL"], port: 25
  end
else
  puts "FC_MAIL ENV not set, mail sending disabled"
end

class Release
  attr_reader :ref, :pusher, :repo_name, :version_iri, :version_info

  def initialize(name, payload)
    @base_path = "/tmp/friend_computer"
    @name = name
    @ref = payload["ref"]
    @url = payload["repository"]["html_url"]
    @repo_name = payload["repository"]["name"]
    @pusher = payload["sender"]["login"]
  end

  def clone_repo
    cleanup
    @repo = Git.clone(@url, @repo_name, path: @base_path)
    @repo.fetch
    @repo.checkout(@ref)
  end

  def check_version
    owl = File.open("#{@base_path}/#{@repo_name}/#{@name}.owl") { |f| Nokogiri::XML(f) }
    iri = owl.xpath("//owl:versionIRI/@rdf:resource").first
    @version_iri = iri.value unless iri.nil?
    info = owl.xpath("//owl:versionInfo").first
    @version_info = info.content unless info.nil?
  end

  def cleanup
    FileUtils.remove_dir("#{@base_path}/#{@repo_name}", force: true)
  end
end

post "/payload/:name" do |name|
  if request.env["HTTP_X_GITHUB_EVENT"] == "create"
    payload = JSON.parse(request.body.read)
    return 200 unless payload["ref_type"] == "tag"
    release = Release.new(name, payload) if payload["ref_type"] == "tag"
    release.clone_repo
    release.check_version
    release.cleanup
    message = %(New Release Detected for #{release.repo_name} created by #{release.pusher}

Release Name: #{release.ref}
VersionIRI: #{release.version_iri}
VersionInfo: #{release.version_info})
    puts message
    if ENV.key? "FC_MAIL"
      Mail.deliver do
        from "friend_computer@cafe-trauma.com"
        to ["jrutecht@uams.edu", "MBrochhausen@uams.edu"]
        subject "New Release #{release.repo_name}"
        body message
      end
      puts "Mail dispatched"
    end
  else
    puts "Non-create request sent"
  end
end
