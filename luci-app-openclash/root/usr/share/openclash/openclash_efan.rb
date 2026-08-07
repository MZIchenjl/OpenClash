#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "uri"
require "yaml"
require "zlib"

# Efan account and configuration client.
#
# Sensitive values are never accepted on the command line. Login reads a
# mode-0600 JSON request file and deletes it before returning. curl receives
# passwords and service tokens through mode-0600 files rather than argv.
module OpenClashEfan
  API_BASE = ENV.fetch("OPENCLASH_EFAN_API_BASE", "https://app.eod621808.com")
  ROOT = ENV.fetch("OPENCLASH_EFAN_ROOT", "/etc/openclash")
  CONFIG_DIR = File.join(ROOT, "config")
  CURL_BIN = ENV.fetch("OPENCLASH_EFAN_CURL", "curl")
  MAX_RESPONSE_BYTES = 16 * 1024 * 1024
  # OpenClash's nftables and iptables output chains reserve GID 65534 for
  # traffic that must not be transparently redirected back into Mihomo. Use
  # that same documented-by-implementation bypass for API control traffic.
  OPENCLASH_BYPASS_GID = 65_534
  PRIVATE_KEY_MASK = "encoding".b
  PRIVATE_KEY_BLOB = Base64.decode64(<<~B64).freeze
    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
    RCspIU4xPCVJPjUsOCI7IUklIjxDTkJJRA==
  B64

  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  HttpResult = Struct.new(:status, :body, :curl_exit, :curl_error)

  module_function

  def now
    Time.now.to_i
  end

  def api_host
    uri = URI.parse(API_BASE)
    raise Error.new("invalid_api_host", "Efan API host is invalid") unless uri.host

    uri.host
  rescue URI::InvalidURIError
    raise Error.new("invalid_api_host", "Efan API host is invalid")
  end

  def mihomo_bin
    ENV.fetch("OPENCLASH_EFAN_MIHOMO", "/etc/openclash/core/clash_meta")
  end

  def sanitize_user(email)
    value = email.to_s.strip.downcase
    raise Error.new("invalid_email", "email is required") if value.empty? || value.bytesize > 254
    raise Error.new("invalid_email", "email format is invalid") unless value.match?(/\A[^\s@]+@[^\s@]+\z/)

    component = value.gsub(/[^a-z0-9@._+\-]/, "_")[0, 180]
    raise Error.new("invalid_email", "email cannot be used as a cache name") if component.empty?

    component
  end

  def sanitize_service_id(id)
    component = id.to_s.gsub(/[^A-Za-z0-9._+\-]/, "_")[0, 96]
    raise Error.new("invalid_service", "service id is missing") if component.empty?

    component
  end

  def account_path(email)
    File.join(ROOT, "efan-#{sanitize_user(email)}.json")
  end

  def config_path(email, service_id)
    File.join(CONFIG_DIR, "efan-#{sanitize_user(email)}-#{sanitize_service_id(service_id)}.yaml")
  end

  def all_config_path(email)
    config_path(email, "all")
  end

  def ensure_directories
    Dir.mkdir(ROOT, 0o700) unless Dir.exist?(ROOT)
    File.chmod(0o700, ROOT)
    Dir.mkdir(CONFIG_DIR, 0o700) unless Dir.exist?(CONFIG_DIR)
  rescue SystemCallError => e
    raise Error.new("storage_error", "cannot prepare OpenClash directories: #{e.message}")
  end

  def atomic_write(path, content, mode = 0o600)
    ensure_directories
    temp = "#{path}.tmp.#{$$}.#{rand(1_000_000)}"
    flags = File::WRONLY | File::CREAT | File::EXCL
    File.open(temp, flags, mode) do |file|
      file.write(content)
      file.flush
      file.fsync
    end
    File.chmod(mode, temp)
    File.rename(temp, path)
  rescue SystemCallError => e
    raise Error.new("storage_error", "cannot update #{File.basename(path)}: #{e.message}")
  ensure
    File.delete(temp) if defined?(temp) && File.exist?(temp)
  end

  # A converted file is never allowed to replace the last-known-good file
  # until the exact Mihomo core used by OpenClash accepts it. Tests may opt out
  # explicitly because the upstream Mihomo binary cannot parse type=x365.
  def validate_mihomo_config(content)
    return true if ENV["OPENCLASH_EFAN_SKIP_MIHOMO_VALIDATE"] == "1"
    binary = mihomo_bin
    unless File.file?(binary) && File.executable?(binary)
      raise Error.new("mihomo_missing", "the x365-capable Mihomo core is not installed")
    end

    ensure_directories
    temp = File.join(CONFIG_DIR, ".efan-validate-#{$$}-#{rand(1_000_000)}.yaml")
    File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(content)
      file.flush
      file.fsync
    end
    null = File.open(File::NULL, "w")
    pid = Process.spawn(binary, "-t", "-f", temp, out: null, err: null)
    _, process_status = Process.wait2(pid)
    raise Error.new("mihomo_validation_failed", "the generated Mihomo configuration is invalid") unless process_status.success?

    true
  rescue Error
    raise
  rescue SystemCallError => e
    raise Error.new("mihomo_validation_failed", "cannot validate the generated Mihomo configuration: #{e.class}")
  ensure
    null.close if defined?(null) && null && !null.closed?
    File.delete(temp) if defined?(temp) && temp && File.file?(temp)
  end

  def read_json(path)
    JSON.parse(File.binread(path))
  rescue Errno::ENOENT
    raise Error.new("not_logged_in", "account cache does not exist")
  rescue JSON::ParserError
    raise Error.new("invalid_cache", "account cache is invalid")
  end

  def curl_quote(value)
    text = value.to_s
    raise Error.new("invalid_header", "header contains a line break") if text.include?("\r") || text.include?("\n")

    '"' + text.gsub("\\", "\\\\").gsub('"', '\\"') + '"'
  end

  def http_request(method, path, body: nil, token: nil)
    base = URI.parse(API_BASE)
    unless %w[https http].include?(base.scheme) && base.host
      raise Error.new("invalid_api_host", "Efan API host is invalid")
    end
    if base.scheme != "https" && ENV["OPENCLASH_EFAN_ALLOW_HTTP"] != "1"
      raise Error.new("invalid_api_host", "Efan API must use HTTPS")
    end

    work = File.join("/tmp", "openclash-efan-#{$$}-#{rand(1_000_000)}")
    Dir.mkdir(work, 0o700)
    config_file = File.join(work, "curl.conf")
    response_file = File.join(work, "response")
    body_file = File.join(work, "request.json")
    error_file = File.join(work, "curl.error")
    url = URI.join(API_BASE.end_with?("/") ? API_BASE : API_BASE + "/", path.sub(%r{\A/}, "")).to_s

    if body
      File.open(body_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body) }
    end

    lines = [
      "silent",
      "show-error",
      "location",
      "connect-timeout = 10",
      "max-time = 30",
      "request = #{curl_quote(method)}",
      "url = #{curl_quote(url)}",
      "header = #{curl_quote('Accept: application/json')}",
      "output = #{curl_quote(response_file)}",
      'write-out = "%{http_code}"'
    ]
    lines << "header = #{curl_quote('Content-Type: application/json')}" if body
    lines << "header = #{curl_quote("Authorization: #{token}")}" if token
    lines << "data-binary = #{curl_quote("@#{body_file}")}" if body
    File.open(config_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(lines.join("\n") + "\n")
    end

    read_pipe, write_pipe = IO.pipe
    error_io = File.open(error_file, File::WRONLY | File::CREAT | File::EXCL, 0o600)
    pid = Process.spawn(
      CURL_BIN,
      "--config",
      config_file,
      out: write_pipe,
      err: error_io,
      gid: OPENCLASH_BYPASS_GID
    )
    write_pipe.close
    status_text = read_pipe.read
    read_pipe.close
    _, process_status = Process.wait2(pid)
    error_io.close
    curl_error = File.exist?(error_file) ? File.binread(error_file, 2048).to_s.strip : ""
    response = File.exist?(response_file) ? File.binread(response_file, MAX_RESPONSE_BYTES + 1).to_s : ""
    raise Error.new("response_too_large", "Efan API response is too large") if response.bytesize > MAX_RESPONSE_BYTES

    status = status_text.to_s[/\d{3}\z/].to_i
    HttpResult.new(status, response, process_status.exitstatus, curl_error)
  rescue Error
    raise
  rescue StandardError => e
    raise Error.new("network_error", "Efan API request failed: #{e.message}")
  ensure
    if defined?(work) && work && work.start_with?("/tmp/openclash-efan-") && Dir.exist?(work)
      Dir.entries(work).each do |entry|
        next if entry == "." || entry == ".."
        candidate = File.join(work, entry)
        File.delete(candidate) if File.file?(candidate)
      end
      Dir.rmdir(work) rescue nil
    end
  end

  def parse_json_response(result)
    if result.curl_exit != 0
      message = result.curl_error.empty? ? "curl exit #{result.curl_exit}" : result.curl_error
      raise Error.new("network_error", message[0, 300])
    end
    raise Error.new("http_#{result.status}", "Efan API returned HTTP #{result.status}") unless result.status.between?(200, 299)

    JSON.parse(result.body)
  rescue JSON::ParserError
    raise Error.new("invalid_response", "Efan API returned invalid JSON")
  end

  def normalize_services(data)
    services = data["my_services"]
    raise Error.new("invalid_response", "login response has no my_services array") unless services.is_a?(Array)

    seen = {}
    services.map do |service|
      raise Error.new("invalid_response", "my_services contains a non-object item") unless service.is_a?(Hash)

      id = service["id"]
      token = service["access_token"]
      raise Error.new("invalid_response", "service id is missing") if id.nil? || id.to_s.empty?
      raise Error.new("invalid_response", "service access_token is missing") unless token.is_a?(String) && !token.empty?
      raise Error.new("invalid_response", "duplicate service id") if seen[id.to_s]
      raise Error.new("invalid_response", "service access_token contains a line break") if token.include?("\r") || token.include?("\n")

      seen[id.to_s] = true
      {
        "id" => id,
        "domain" => service["domain"],
        "status" => service["status"],
        "service_name" => service["service_name"],
        "next_due_date" => service["next_due_date"],
        "access_token" => token
      }
    end
  end

  def private_key
    @private_key ||= begin
      pem = PRIVATE_KEY_BLOB.bytes.each_with_index.map do |byte, index|
        byte ^ PRIVATE_KEY_MASK.getbyte(index % PRIVATE_KEY_MASK.bytesize)
      end.pack("C*")
      OpenSSL::PKey::RSA.new(pem)
    end
  end

  # Mirrors protocolabs-comm/comm.DecryptConfigData from efanapp 1.0.40:
  # base64 -> 256-byte RSA PKCS#1 v1.5 blocks -> zlib stream.
  def decrypt_proxy(encoded)
    raise Error.new("invalid_config", "proxy must be a Base64 string") unless encoded.is_a?(String) && !encoded.empty?

    ciphertext = Base64.strict_decode64(encoded)
    block_size = private_key.n.num_bytes
    unless block_size == 256 && !ciphertext.empty? && (ciphertext.bytesize % block_size).zero?
      raise Error.new("invalid_config", "proxy ciphertext has an invalid length")
    end
    compressed = ciphertext.bytes.each_slice(block_size).map do |chunk|
      private_key.private_decrypt(chunk.pack("C*"), OpenSSL::PKey::RSA::PKCS1_PADDING)
    end.join
    Zlib::Inflate.inflate(compressed)
  rescue ArgumentError, OpenSSL::PKey::RSAError, Zlib::Error => e
    raise Error.new("decrypt_failed", "cannot decrypt Efan proxy data: #{e.class}")
  end

  def safe_yaml_load(text)
    if YAML.respond_to?(:safe_load)
      YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    else
      YAML.load(text)
    end
  rescue ArgumentError
    # Psych versions shipped by older OpenWrt releases use positional args.
    YAML.safe_load(text, [], [], false)
  rescue Psych::Exception => e
    raise Error.new("invalid_config", "decrypted proxy YAML is invalid: #{e.class}")
  end

  def query_values(uri)
    pairs = URI.decode_www_form(uri.query.to_s)
    grouped = pairs.group_by(&:first)
    allowed = %w[path host sni pbk sid]
    unknown = grouped.keys - allowed
    raise Error.new("invalid_node", "x365 URI contains unsupported query fields") unless unknown.empty?
    grouped.each_with_object({}) do |(key, values), output|
      raise Error.new("invalid_node", "x365 URI contains duplicate #{key}") unless values.length == 1
      output[key] = values.first[1]
    end
  end

  def parse_x365(name, raw_uri, udp: true)
    uri = URI.parse(raw_uri.to_s)
    raise Error.new("invalid_node", "node #{name} is not x365") unless uri.scheme == "x365"
    raise Error.new("invalid_node", "node #{name} has no server") if uri.hostname.to_s.empty?
    raise Error.new("invalid_node", "node #{name} has an invalid port") unless uri.port && uri.port.between?(1, 65_535)

    uuid = URI::DEFAULT_PARSER.unescape(uri.user.to_s)
    unless uuid.match?(/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/)
      raise Error.new("invalid_node", "node #{name} has an invalid UUID")
    end
    query = query_values(uri)
    %w[path host sni pbk sid].each do |key|
      raise Error.new("invalid_node", "node #{name} is missing #{key}") if query[key].to_s.empty?
    end
    raise Error.new("invalid_node", "node #{name} has an invalid public key") unless query["pbk"].match?(/\A[A-Za-z0-9_-]{43}\z/)
    raise Error.new("invalid_node", "node #{name} has an invalid short id") unless query["sid"].match?(/\A(?:[0-9a-fA-F]{2}){1,8}\z/)

    {
      "name" => name.to_s,
      "type" => "x365",
      "server" => uri.hostname,
      "port" => uri.port,
      "uuid" => uuid.downcase,
      "host" => query["host"],
      "path" => query["path"],
      "sni" => query["sni"],
      "transport" => "h2",
      "client-fingerprint" => "chrome",
      "reality-opts" => {
        "public-key" => query["pbk"],
        "short-id" => query["sid"].downcase
      },
      "udp" => udp
    }
  rescue URI::InvalidURIError
    raise Error.new("invalid_node", "node #{name} has an invalid x365 URI")
  end

  def domain_rules(values, policy)
    Array(values).each_with_object([]) do |raw, rules|
      domain = raw.to_s.strip.sub(/\A\+\./, "")
      next if domain.empty? || domain.include?(",")
      rules << "DOMAIN-SUFFIX,#{domain},#{policy}"
    end
  end

  def mihomo_nameservers(values)
    supported = %w[udp tcp tls http https quic system ts tailscale dhcp rcode]
    Array(values).map(&:to_s).map(&:strip).reject(&:empty?).select do |server|
      scheme = server[/\A([A-Za-z][A-Za-z0-9+.-]*):\/\//, 1]
      scheme.nil? || supported.include?(scheme.downcase)
    end
  end

  def convert_config(app_data, service, udp: true)
    unless app_data.is_a?(Hash) && app_data["proxy"].is_a?(String) && app_data["servers"].is_a?(Array) && app_data["user"].is_a?(Hash)
      raise Error.new("invalid_config", "app response must contain proxy, servers, and user")
    end

    source = safe_yaml_load(decrypt_proxy(app_data["proxy"]))
    unless source.is_a?(Hash) && source["proxies"].is_a?(Hash)
      raise Error.new("invalid_config", "decrypted YAML has no proxies map")
    end

    metadata = app_data["servers"].select { |item| item.is_a?(Hash) && item["name"].is_a?(String) }
    metadata_by_name = metadata.each_with_object({}) { |item, memo| memo[item["name"]] = item }
    ordered_names = source["proxies"].keys.select do |name|
      item = metadata_by_name[name]
      item.nil? || item["show"].to_i != 0
    end.sort_by do |name|
      item = metadata_by_name[name]
      item ? [item["sort_order"].to_i, item["id"].to_i, name.to_s] : [2**31, 2**31, name.to_s]
    end

    proxies = []
    ordered_names.each do |name|
      values = Array(source["proxies"][name])
      values.each_with_index do |raw_uri, index|
        node_name = values.length == 1 ? name.to_s : "#{name} ##{index + 1}"
        proxies << parse_x365(node_name, raw_uri, udp: udp)
      end
    end
    raise Error.new("invalid_config", "no visible x365 nodes were found") if proxies.empty?

    names = proxies.map { |proxy| proxy["name"] }
    service_name = service["service_name"].to_s.gsub(/[\r\n]/, " ").strip[0, 80]
    service_name = "Efan service #{service['id']}" if service_name.empty?
    group_name = "Efan - #{service_name}"
    auto_group_name = "#{group_name} Auto"
    output = {
      "mixed-port" => (source["port"].to_i.between?(1, 65_535) ? source["port"].to_i : 7890),
      "allow-lan" => true,
      "mode" => "rule",
      "log-level" => "info",
      "proxies" => proxies,
      "proxy-groups" => [
        {"name" => group_name, "type" => "select", "proxies" => [auto_group_name] + names},
        {"name" => auto_group_name, "type" => "url-test", "url" => "https://www.gstatic.com/generate_204", "interval" => 300, "proxies" => names}
      ],
      "rules" => ["DOMAIN,#{api_host},DIRECT"] + domain_rules(source["direct_domain"], "DIRECT") +
        domain_rules(source["proxy_domain"], group_name) + ["MATCH,#{group_name}"]
    }

    nameservers = mihomo_nameservers(source["domain_resolver"])
    defaults = mihomo_nameservers(source["local_dns"])
    unless nameservers.empty?
      output["dns"] = {"enable" => true, "nameserver" => nameservers}
      output["dns"]["default-nameserver"] = defaults unless defaults.empty?
    end
    "# Generated from Efan service #{service_name}\n" + YAML.dump(output)
  end

  # OpenClash activates one Mihomo configuration at a time. Keep the required
  # per-service files, and also build an account-wide file so every service can
  # be selected without switching the active configuration.
  def build_all_config(email, services)
    proxies = []
    service_groups = []
    service_choices = []
    nameservers = []
    default_nameservers = []

    services.each do |service|
      path = config_path(email, service["id"])
      next unless File.file?(path)

      source = safe_yaml_load(File.binread(path))
      next unless source.is_a?(Hash) && source["proxies"].is_a?(Array) && !source["proxies"].empty?

      service_name = service["service_name"].to_s.gsub(/[\r\n]/, " ").strip[0, 80]
      service_name = "Efan service" if service_name.empty?
      group_name = "Efan - #{service_name} (#{sanitize_service_id(service['id'])})"
      auto_group_name = "#{group_name} Auto"
      node_names = []
      source["proxies"].each do |raw_proxy|
        next unless raw_proxy.is_a?(Hash) && !raw_proxy["name"].to_s.empty?

        proxy = raw_proxy.dup
        proxy["name"] = "#{service_name} / #{raw_proxy['name']}"
        suffix = 2
        candidate = proxy["name"]
        while proxies.any? { |item| item["name"] == candidate }
          candidate = "#{proxy['name']} ##{suffix}"
          suffix += 1
        end
        proxy["name"] = candidate
        proxies << proxy
        node_names << candidate
      end
      next if node_names.empty?

      service_choices << group_name
      service_groups << {"name" => group_name, "type" => "select", "proxies" => [auto_group_name] + node_names}
      service_groups << {
        "name" => auto_group_name,
        "type" => "url-test",
        "url" => "https://www.gstatic.com/generate_204",
        "interval" => 300,
        "proxies" => node_names
      }
      dns = source["dns"]
      if dns.is_a?(Hash)
        nameservers.concat(Array(dns["nameserver"]))
        default_nameservers.concat(Array(dns["default-nameserver"]))
      end
    end
    return nil if service_choices.empty?

    output = {
      "mixed-port" => 7890,
      "allow-lan" => true,
      "mode" => "rule",
      "log-level" => "info",
      "proxies" => proxies,
      "proxy-groups" => [
        {"name" => "Efan Services", "type" => "select", "proxies" => service_choices}
      ] + service_groups,
      "rules" => ["DOMAIN,#{api_host},DIRECT", "MATCH,Efan Services"]
    }
    nameservers = nameservers.compact.map(&:to_s).reject(&:empty?).uniq
    default_nameservers = default_nameservers.compact.map(&:to_s).reject(&:empty?).uniq
    unless nameservers.empty?
      output["dns"] = {"enable" => true, "nameserver" => nameservers}
      output["dns"]["default-nameserver"] = default_nameservers unless default_nameservers.empty?
    end
    "# Generated from every cached Efan service\n" + YAML.dump(output)
  end

  def update_all_config(email, services)
    yaml = build_all_config(email, services)
    return nil unless yaml

    path = all_config_path(email)
    validate_mihomo_config(yaml)
    atomic_write(path, yaml, 0o600)
    path
  end

  def fetch_service(email, service, udp: true)
    result = http_request("GET", "/v1/app?flag=wassvpn", token: service.fetch("access_token"))
    if [401, 403].include?(result.status)
      return {
        "id" => service["id"],
        "name" => service["service_name"],
        "account_status" => service["status"],
        "status" => "auth_invalid",
        "http_status" => result.status
      }
    end
    app_data = parse_json_response(result)
    yaml = convert_config(app_data, service, udp: udp)
    target = config_path(email, service["id"])
    validate_mihomo_config(yaml)
    atomic_write(target, yaml, 0o600)
    {
      "id" => service["id"],
      "name" => service["service_name"],
      "account_status" => service["status"],
      "status" => "updated",
      "config" => target,
      "nodes" => safe_yaml_load(yaml)["proxies"].length,
      "updated_at" => now
    }
  rescue Error => e
    {
      "id" => service["id"],
      "name" => service["service_name"],
      "account_status" => service["status"],
      "status" => "error",
      "error" => e.code,
      "message" => e.message
    }
  end

  def refresh_cache(cache, udp: true)
    email = cache["email"]
    services = cache["services"]
    raise Error.new("invalid_cache", "account cache has no services") unless services.is_a?(Array)

    results = services.map { |service| fetch_service(email, service, udp: udp) }
    update_all_config(email, services)
    if results.any? { |item| item["status"] == "auth_invalid" }
      File.delete(account_path(email)) if File.exist?(account_path(email))
    else
      by_id = results.each_with_object({}) { |item, memo| memo[item["id"].to_s] = item }
      services.each do |service|
        item = by_id[service["id"].to_s]
        service["last_fetch_status"] = item["status"]
        service["last_fetched_at"] = item["updated_at"] if item["updated_at"]
        service["last_node_count"] = item["nodes"] if item["nodes"]
      end
      cache["updated_at"] = now
      atomic_write(account_path(email), JSON.pretty_generate(cache) + "\n", 0o600)
    end
    results
  end

  def login(input_path, udp: true)
    request = read_json(input_path)
    email = request["email"].to_s.strip.downcase
    password = request["password"]
    sanitize_user(email)
    raise Error.new("invalid_password", "password is required") unless password.is_a?(String) && !password.empty?

    result = http_request("POST", "/v1/login", body: JSON.generate("email" => email, "password" => password))
    response = parse_json_response(result)
    unless response["code"].to_i.zero? && response["data"].is_a?(Hash)
      message = response["message"].to_s
      message = "login failed" if message.empty?
      raise Error.new("login_failed", message[0, 300])
    end
    services = normalize_services(response["data"])
    cache = {"schema" => 1, "email" => email, "services" => services, "updated_at" => now}
    atomic_write(account_path(email), JSON.pretty_generate(cache) + "\n", 0o600)
    results = refresh_cache(cache, udp: udp)
    operation_result(email, results)
  ensure
    File.delete(input_path) if input_path && File.file?(input_path)
  end

  def refresh(email, udp: true)
    cache = read_json(account_path(email))
    results = refresh_cache(cache, udp: udp)
    operation_result(cache["email"], results)
  end

  def logout(email)
    path = account_path(email)
    existed = File.exist?(path)
    File.delete(path) if existed
    {
      "status" => "ok",
      "session_state" => "logged_out",
      "email" => email.to_s.strip.downcase,
      "account_cache_deleted" => existed,
      "configs_preserved" => true
    }
  end

  def status(email)
    return discovered_status if email.to_s.strip.empty?

    cache = read_json(account_path(email))
    services = cache.fetch("services", []).map do |service|
      {
        "id" => service["id"],
        "name" => service["service_name"],
        "account_status" => service["status"],
        "status" => service["last_fetch_status"] || (File.file?(config_path(cache["email"], service["id"])) ? "cached" : "not_fetched"),
        "last_fetch_status" => service["last_fetch_status"],
        "last_fetched_at" => service["last_fetched_at"],
        "nodes" => service["last_node_count"],
        "config" => config_path(cache["email"], service["id"]),
        "config_exists" => File.file?(config_path(cache["email"], service["id"]))
      }
    end
    {
      "status" => "ok",
      "session_state" => "logged_in",
      "email" => cache["email"],
      "updated_at" => cache["updated_at"],
      "remembered_on_router" => true,
      "all_config" => all_config_path(cache["email"]),
      "all_config_exists" => File.file?(all_config_path(cache["email"])),
      "services" => services
    }.merge(fetch_summary(services))
  end

  def fetch_summary(results)
    total = results.length
    ready = results.count do |item|
      %w[updated cached ready].include?(item["status"].to_s) ||
        %w[updated cached ready].include?(item["last_fetch_status"].to_s) ||
        (item["config_exists"] && item["last_fetch_status"].to_s.empty?)
    end
    auth_invalid = results.count do |item|
      item["status"] == "auth_invalid" || item["last_fetch_status"] == "auth_invalid"
    end
    failed = total - ready - auth_invalid
    fetch_state = if auth_invalid.positive?
                    "auth_invalid"
                  elsif total.zero?
                    "empty"
                  elsif ready == total
                    "ready"
                  elsif ready.positive?
                    "partial"
                  else
                    "failed"
                  end
    {
      "fetch_state" => fetch_state,
      "service_count" => total,
      "ready_count" => ready,
      "failed_count" => failed,
      "auth_invalid_count" => auth_invalid
    }
  end

  def operation_result(email, results)
    logged_in = File.file?(account_path(email))
    output = {
      "status" => logged_in ? "ok" : "error",
      "session_state" => logged_in ? "logged_in" : "expired",
      "email" => email,
      "remembered_on_router" => logged_in,
      "all_config" => all_config_path(email),
      "all_config_exists" => File.file?(all_config_path(email)),
      "services" => results
    }.merge(fetch_summary(results))
    unless logged_in
      output["error"] = "service_auth_invalid"
      output["message"] = "one or more service tokens are invalid; please log in again"
    end
    output
  end

  def discovered_status
    accounts = Dir.glob(File.join(ROOT, "efan-*.json")).each_with_object([]) do |path, list|
      begin
        cache = JSON.parse(File.binread(path))
        email = cache["email"].to_s
        next if email.empty? || !cache["services"].is_a?(Array)

        list << {
          "email" => email,
          "updated_at" => cache["updated_at"],
          "service_count" => cache["services"].length,
          "all_config_exists" => File.file?(all_config_path(email))
        }
      rescue JSON::ParserError, SystemCallError, Error
        next
      end
    end.sort_by { |account| -account["updated_at"].to_i }

    return {"status" => "ok", "session_state" => "logged_out", "accounts" => []} if accounts.empty?

    status(accounts.first["email"]).merge("accounts" => accounts)
  end

  def run(argv)
    command = argv.shift
    result = case command
             when "login"
               input = argv.shift
               raise Error.new("usage", "login requires a request file") unless input && argv.empty?
               login(input)
             when "refresh"
               email = argv.shift
               raise Error.new("usage", "refresh requires an email") unless email && argv.empty?
               refresh(email)
             when "logout"
               email = argv.shift
               raise Error.new("usage", "logout requires an email") unless email && argv.empty?
               logout(email)
             when "status"
               email = argv.shift
               raise Error.new("usage", "status requires an email") unless email && argv.empty?
               status(email)
             else
               raise Error.new("usage", "usage: openclash_efan.rb login REQUEST.json | refresh EMAIL | status EMAIL | logout EMAIL")
             end
    puts JSON.generate(result)
    0
  rescue Error => e
    puts JSON.generate("status" => "error", "error" => e.code, "message" => e.message)
    1
  rescue StandardError => e
    puts JSON.generate("status" => "error", "error" => "internal_error", "message" => e.class.name)
    1
  end
end

exit(OpenClashEfan.run(ARGV)) if $PROGRAM_NAME == __FILE__
