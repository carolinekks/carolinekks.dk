class ChangelogController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :index, :refresh, :webhook ]

  def index
    begin
      cache_key = "github_commits_#{Time.now.strftime('%Y%m%d%H%M')[0..-2]}0"
      commits = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
        fetch_github_commits
      end

      filtered_commits = commits.select do |commit|
        commit[:stats][:total] > 50
      end

      if filtered_commits.empty?
        filtered_commits = [
          {
            date: Date.today.iso8601,
            title: "No Significant Changes",
            details: [ "All recent changes were minor (50 lines or less)" ],
            sha: "filtered",
            url: "https://github.com/carolinekks/carolinekks.dk",
            stats: { additions: 0, deletions: 0, total: 0 }
          }
        ]
      end

      render json: filtered_commits
    rescue => e
      Rails.logger.error "Changelog controller error: #{e.message}"
      render json: [
        {
          date: Date.today.iso8601,
          title: "Development Mode",
          details: [ "GitHub API integration in progress" ],
          sha: "dev",
          url: "https://github.com/carolinekks/carolinekks.dk",
          stats: { additions: 0, deletions: 0, total: 0 }
        }
      ]
    end
  end

  def refresh
    begin
      Rails.cache.delete_matched("github_commits_*")

      fresh_commits = fetch_github_commits

      cache_key = "github_commits_#{Time.now.strftime('%Y%m%d%H%M')[0..-2]}0"
      Rails.cache.write(cache_key, fresh_commits, expires_in: 10.minutes)

      filtered_commits = fresh_commits.select do |commit|
        commit[:stats][:total] > 50
      end

      if filtered_commits.empty?
        filtered_commits = [
          {
            date: Date.today.iso8601,
            title: "No Significant Changes",
            details: [ "All recent changes were minor (50 lines or less)" ],
            sha: "filtered",
            url: "https://github.com/carolinekks/carolinekks.dk",
            stats: { additions: 0, deletions: 0, total: 0 }
          }
        ]
      end

      render json: {
        message: "Cache refreshed successfully",
        commits: filtered_commits,
        timestamp: Time.current.iso8601
      }
    rescue => e
      Rails.logger.error "Cache refresh error: #{e.message}"
      render json: {
        error: "Failed to refresh cache: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def webhook
    if valid_github_webhook?(request)
      Rails.cache.delete_matched("github_commits_*")
      Rails.logger.info "GitHub webhook received - cleared changelog cache"

      head :ok
    else
      Rails.logger.warn "Invalid GitHub webhook attempt - signature verification failed"
      head :unauthorized
    end
  end

  private

  def valid_github_webhook?(request)
    signature = request.headers["X-Hub-Signature-256"]

    return false unless signature

    payload_body = request.body.read

    secret = Rails.application.credentials.github_webhook_secret

    return false unless secret

    expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      secret,
      payload_body
    )

    Rack::Utils.secure_compare(signature, expected_signature)
  rescue => e
    Rails.logger.error "Webhook validation error: #{e.message}"
    false
  end

  def fetch_github_commits
    require "open-uri"
    require "json"

    repo_path = "carolinekks/carolinekks.dk"
    url = "https://api.github.com/repos/#{repo_path}/commits?per_page=10"

    Rails.logger.info "Fetching commits from: #{url}"

    begin
      response = URI.open(url,
        "User-Agent" => "carolinekks.dk-Rails-App",
        "Accept" => "application/vnd.github.v3+json",
        :read_timeout => 10
      ).read

      commits_data = JSON.parse(response)
      Rails.logger.info "Successfully parsed #{commits_data.size} commits"

      if commits_data.empty?
        return [
          {
            date: Date.today.strftime("%Y-%m-%d"),
            title: "No Commits Found",
            details: [ "The repository exists but has no commits yet." ],
            sha: "empty",
            url: "https://github.com/#{repo_path}",
            stats: { additions: 0, deletions: 0, total: 0 }
          }
        ]
      end

      commits_data.map do |commit|
        process_commit_with_stats(commit, repo_path)
      end

    rescue OpenURI::HTTPError => e
      Rails.logger.error "HTTP Error: #{e.message}"
      [
        {
          date: Date.today.strftime("%Y-%m-%d"),
          title: "HTTP Error #{e.io.status[0]}",
          details: [ "GitHub API returned an error.", "Message: #{e.message}" ],
          sha: "http_error",
          url: "https://github.com/#{repo_path}",
          stats: { additions: 0, deletions: 0, total: 0 }
        }
      ]
    rescue => e
      Rails.logger.error "Error in fetch_github_commits: #{e.message}"
      [
        {
          date: Date.today.strftime("%Y-%m-%d"),
          title: "Connection Issue",
          details: [ "Error: #{e.message}", "This usually works in production." ],
          sha: "error",
          url: "https://github.com/#{repo_path}",
          stats: { additions: 0, deletions: 0, total: 0 }
        }
      ]
    end
  end

  def process_commit_with_stats(commit, repo_path)
    commit_info = commit["commit"] || {}
    author_info = commit_info["author"] || {}
    message = commit_info["message"] || "No message"

    stats = commit["stats"] || {}
    additions = stats["additions"] || 0
    deletions = stats["deletions"] || 0
    total = stats["total"] || (additions + deletions)

    if additions == 0 && deletions == 0
      stats = fetch_commit_stats(commit["sha"], repo_path)
      additions = stats[:additions]
      deletions = stats[:deletions]
      total = stats[:total]
    end

    date_string = author_info["date"]
    formatted_date = if date_string
      begin
        DateTime.parse(date_string).strftime("%Y-%m-%d")
      rescue
        Date.today.strftime("%Y-%m-%d")
      end
    else
      Date.today.strftime("%Y-%m-%d")
    end

    message_lines = message.split("\n")
    title = message_lines.first || "No title"
    details = message_lines[1..-1] || []
    details = details.reject { |line| line.strip.empty? }

    {
      date: formatted_date,
      title: title,
      details: details,
      sha: commit["sha"] ? commit["sha"][0, 7] : "unknown",
      url: commit["html_url"] || "#",
      stats: {
        additions: additions,
        deletions: deletions,
        total: total
      }
    }
  end

  def fetch_commit_stats(commit_sha, repo_path)
    commit_url = "https://api.github.com/repos/#{repo_path}/commits/#{commit_sha}"

    begin
      detailed_response = URI.open(commit_url,
        "User-Agent" => "carolinekks.dk-Rails-App",
        "Accept" => "application/vnd.github.v3+json",
        :read_timeout => 5
      ).read

      detailed_commit = JSON.parse(detailed_response)
      stats = detailed_commit["stats"] || {}

      {
        additions: stats["additions"] || 0,
        deletions: stats["deletions"] || 0,
        total: stats["total"] || 0
      }
    rescue => e
      Rails.logger.warn "Could not fetch stats for commit #{commit_sha}: #{e.message}"
      { additions: 0, deletions: 0, total: 0 }
    end
  end
end
