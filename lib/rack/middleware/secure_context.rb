# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Rack::Middleware
  class SecureContext
    # Robust yet lightweight security patterns to block SQL Injection, Path Traversal, and Exploit Payloads
    ATTACK_PATTERNS = [
      # 1. SQL Injection Signatures
      /\b(union\s+select|insert\s+into|delete\s+from|drop\s+table|update\s+\w+\s+set|benchmark\s*\(|sleep\s*\(|waitfor\s+delay)\b/i,
      /(?:'|%27)\s*(?:or|and)\s*(?:'|%27)?\w+(?:'|%27)?\s*=\s*(?:'|%27)?\w+/i,
      /(?:'|%27)\s*(?:--|#|\/\*)/,
      /\b(information_schema|load_file|into\s+outfile)\b/i,

      # 2. Path Traversal & LFI
      /(?:\.\.[\/\\]|%2e%2e(?:%2f|%5c)|\/etc\/passwd|boot\.ini)/i,

      # 3. Cross-Site Scripting (XSS) in URL
      /(?:<script|%3cscript|javascript:|onerror\s*=|onload\s*=|document\.cookie)/i,

      # 4. Null Byte Injection
      /(?:\x00|%00)/
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      if suspicious_request?(env)
        log_security_alert(env)
        return forbidden_response
      end

      if Session.secure_flag?
        mark_as_https(env)
      end

      status, headers, body = @app.call(env)

      # Ensure standard HTTP security headers on all responses
      headers['X-Content-Type-Options'] ||= 'nosniff'
      headers['X-XSS-Protection']       ||= '1; mode=block'
      headers['X-Frame-Options']        ||= 'SAMEORIGIN'
      headers['Referrer-Policy']        ||= 'strict-origin-when-cross-origin'

      [status, headers, body]
    end

    private

    def suspicious_request?(env)
      path  = env['PATH_INFO'].to_s
      query = env['QUERY_STRING'].to_s

      return true if matches_patterns?(path)
      return true if matches_patterns?(query)

      false
    end

    def matches_patterns?(string)
      return false if string.blank?

      decoded = begin
        URI.decode_www_form_component(string)
      rescue => _e
        string
      end

      [string, decoded].any? do |val|
        ATTACK_PATTERNS.any? { |pattern| val.match?(pattern) }
      end
    end

    def log_security_alert(env)
      ip = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR'] || 'unknown'
      path = env['PATH_INFO']
      query = env['QUERY_STRING']
      Rails.logger.warn("[SECURITY SHIELD] Blocked suspicious request from #{ip} | Path: #{path} | Query: #{query}")
    end

    def forbidden_response
      [
        403,
        {
          'Content-Type' => 'application/json; charset=utf-8',
          'X-Security-Shield' => 'Blocked'
        },
        ['{"error":"Akses Ditolak: Permintaan diblokir oleh sistem keamanan karena mengandung karakter berbahaya atau parameter tidak valid.","code":"security_violation"}']
      ]
    end

    def mark_as_https(env)
      # This flag marks Rails environment as SSL, forcing secure flag on cookies.
      # But it does not override request.ssl?.
      # Thus non-HTTPS requests will not be marked as SSL, and secure cookies won't be set.
      env['action_dispatch.ssl'] = true
    end
  end
end
