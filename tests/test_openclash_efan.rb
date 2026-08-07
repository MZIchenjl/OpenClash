# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require "yaml"
require "zlib"

TEST_ROOT = Dir.mktmpdir("openclash-efan-test-")
ENV["OPENCLASH_EFAN_ROOT"] = TEST_ROOT
load File.expand_path("../luci-app-openclash/root/usr/share/openclash/openclash_efan.rb", __dir__)

class OpenClashEfanTest < Minitest::Test
  TEST_UUID = "00112233-4455-6677-8899-aabbccddeeff"
  TEST_PBK = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  TEST_SID = "0123456789abcdef"

  def setup
    FileUtils.rm_rf(TEST_ROOT)
    FileUtils.mkdir_p(File.join(TEST_ROOT, "config"), mode: 0o700)
  end

  def teardown
    restore_http_request
  end

  def test_cache_names_are_stable_and_path_safe
    assert_equal File.join(TEST_ROOT, "efan-user+tag@example.com.json"),
                 OpenClashEfan.account_path(" User+Tag@Example.com ")
    assert_equal File.join(TEST_ROOT, "config", "efan-user@example.com-42.yaml"),
                 OpenClashEfan.config_path("user@example.com", 42)
    assert_raises(OpenClashEfan::Error) { OpenClashEfan.account_path("../../etc/passwd") }
  end

  def test_confirmed_rsa_chunk_and_zlib_decryption
    plaintext = fixture_source_yaml
    encrypted = encrypt_proxy(plaintext)
    assert_equal plaintext, OpenClashEfan.decrypt_proxy(encrypted)
  end

  def test_converter_sorts_hides_and_maps_x365_fields
    app = fixture_app_data([
      {"id" => 2, "name" => "Hidden", "show" => 0, "sort_order" => 1},
      {"id" => 1, "name" => "Visible", "show" => 1, "sort_order" => 2}
    ], {
      "Hidden" => [fixture_uri("hidden")],
      "Visible" => [fixture_uri("visible")]
    })
    output = YAML.safe_load(OpenClashEfan.convert_config(app, {"id" => 9, "service_name" => "Primary"}))

    assert_equal 1, output.fetch("proxies").length
    proxy = output.fetch("proxies").first
    assert_equal "Visible", proxy["name"]
    assert_equal "x365", proxy["type"]
    assert_equal "edge.example", proxy["server"]
    assert_equal "/visible", proxy["path"]
    assert_equal TEST_PBK, proxy.dig("reality-opts", "public-key")
    assert_equal true, proxy["udp"]
    assert_equal ["https://1.1.1.1/dns-query"], output.dig("dns", "nameserver")
  end

  def test_login_fetches_every_service_and_writes_independent_configs
    app = fixture_app_data([
      {"id" => 1, "name" => "Visible", "show" => 1, "sort_order" => 1}
    ], {"Visible" => [fixture_uri("one")]})
    calls = []
    stub_http_request do |method, path, options|
      calls << [method, path, options[:token]]
      if path == "/v1/login"
        data = {
          "code" => 0,
          "message" => "ok",
          "data" => {
            "token" => "unused-account-token",
            "user" => {},
            "my_services" => [
              service(101, "First", "service-token-a"),
              service(202, "Second", "service-token-b")
            ]
          }
        }
        OpenClashEfan::HttpResult.new(200, JSON.generate(data), 0, "")
      else
        OpenClashEfan::HttpResult.new(200, JSON.generate(app), 0, "")
      end
    end

    request = File.join(TEST_ROOT, "login.json")
    File.open(request, "w", 0o600) { |file| file.write(JSON.generate("email" => "user@example.com", "password" => "not-persisted")) }
    result = OpenClashEfan.login(request)

    assert_equal ["service-token-a", "service-token-b"], calls.drop(1).map(&:last)
    assert_equal [101, 202], result.fetch("services").map { |item| item["id"] }
    assert File.file?(OpenClashEfan.config_path("user@example.com", 101))
    assert File.file?(OpenClashEfan.config_path("user@example.com", 202))
    assert File.file?(OpenClashEfan.all_config_path("user@example.com"))
    refute File.exist?(request)

    combined = YAML.safe_load(File.binread(OpenClashEfan.all_config_path("user@example.com")))
    assert_equal "Efan Services", combined.fetch("proxy-groups").first.fetch("name")
    assert_equal ["Efan - First (101)", "Efan - Second (202)"],
                 combined.fetch("proxy-groups").first.fetch("proxies")
    assert_equal ["First / Visible", "Second / Visible"], combined.fetch("proxies").map { |proxy| proxy["name"] }
    assert_equal "MATCH,Efan Services", combined.fetch("rules").last

    cache_text = File.binread(OpenClashEfan.account_path("user@example.com"))
    assert_includes cache_text, "service-token-a"
    refute_includes cache_text, "not-persisted"
    assert_equal 0o600, File.stat(OpenClashEfan.account_path("user@example.com")).mode & 0o777
  end

  def test_auth_failure_deletes_account_cache_but_preserves_yaml
    write_cache
    config = OpenClashEfan.config_path("user@example.com", 101)
    File.write(config, "last-known-good\n")
    stub_http_request do |_method, _path, _options|
      OpenClashEfan::HttpResult.new(401, "{}", 0, "")
    end

    result = OpenClashEfan.refresh("user@example.com")
    assert_equal "auth_invalid", result.fetch("services").first["status"]
    refute File.exist?(OpenClashEfan.account_path("user@example.com"))
    assert_equal "last-known-good\n", File.binread(config)
  end

  def test_server_error_keeps_account_cache_and_yaml
    write_cache
    config = OpenClashEfan.config_path("user@example.com", 101)
    File.write(config, "last-known-good\n")
    stub_http_request do |_method, _path, _options|
      OpenClashEfan::HttpResult.new(503, "{}", 0, "")
    end

    result = OpenClashEfan.refresh("user@example.com")
    assert_equal "error", result.fetch("services").first["status"]
    assert File.exist?(OpenClashEfan.account_path("user@example.com"))
    assert_equal "last-known-good\n", File.binread(config)
  end

  def test_logout_only_deletes_account_cache
    write_cache
    config = OpenClashEfan.config_path("user@example.com", 101)
    File.write(config, "cached\n")

    result = OpenClashEfan.logout("user@example.com")
    assert_equal true, result["account_cache_deleted"]
    assert_equal true, result["configs_preserved"]
    refute File.exist?(OpenClashEfan.account_path("user@example.com"))
    assert File.exist?(config)
  end

  private

  def fixture_uri(path)
    "x365://#{TEST_UUID}@edge.example:443?path=%2F#{path}&host=authority.example&sni=reality.example&pbk=#{TEST_PBK}&sid=#{TEST_SID}"
  end

  def fixture_source_yaml(proxies = {"Visible" => [fixture_uri("fixture")]})
    YAML.dump(
      "port" => 7897,
      "direct_domain" => ["direct.example"],
      "proxy_domain" => ["proxy.example"],
      "domain_resolver" => ["h3://1.1.1.1/dns-query", "https://1.1.1.1/dns-query"],
      "local_dns" => ["1.1.1.1"],
      "proxies" => proxies
    )
  end

  def fixture_app_data(servers, proxies)
    {"proxy" => encrypt_proxy(fixture_source_yaml(proxies)), "servers" => servers, "user" => {}}
  end

  def encrypt_proxy(plaintext)
    compressed = Zlib::Deflate.deflate(plaintext)
    encrypted = compressed.bytes.each_slice(245).map do |chunk|
      OpenClashEfan.private_key.public_encrypt(chunk.pack("C*"), OpenSSL::PKey::RSA::PKCS1_PADDING)
    end.join
    Base64.strict_encode64(encrypted)
  end

  def service(id, name, token)
    {"id" => id, "domain" => "", "status" => "Active", "service_name" => name,
     "next_due_date" => "2030-01-01T00:00:00Z", "access_token" => token}
  end

  def write_cache
    cache = {"schema" => 1, "email" => "user@example.com", "services" => [service(101, "First", "service-token-a")], "updated_at" => 1}
    OpenClashEfan.atomic_write(OpenClashEfan.account_path("user@example.com"), JSON.pretty_generate(cache) + "\n")
  end

  def stub_http_request(&block)
    @original_http_request ||= OpenClashEfan.method(:http_request)
    OpenClashEfan.define_singleton_method(:http_request) do |method, path, body: nil, token: nil|
      block.call(method, path, {body: body, token: token})
    end
  end

  def restore_http_request
    return unless @original_http_request

    original = @original_http_request
    OpenClashEfan.define_singleton_method(:http_request) do |*args, **kwargs|
      original.call(*args, **kwargs)
    end
    @original_http_request = nil
  end
end

Minitest.after_run { FileUtils.rm_rf(TEST_ROOT) }
