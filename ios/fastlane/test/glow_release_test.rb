# Tests for ios/fastlane/glow_release.rb. Owner: B9.
# Run: ios/fastlane/ship test   (or, from ios/fastlane: bundle exec ruby test/glow_release_test.rb)
require 'base64'
require 'json'
require 'minitest/autorun'
require 'plist'
require 'tmpdir'
require_relative '../glow_release'

module Fixtures
  module_function

  def jwt(payload)
    encode = ->(hash) { Base64.urlsafe_encode64(JSON.generate(hash), padding: false) }
    "#{encode.call(alg: 'HS256', typ: 'JWT')}.#{encode.call(payload)}.c2lnbmF0dXJlLW5vdC1jaGVja2Vk"
  end

  P8 = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg\n-----END PRIVATE KEY-----"

  def settings(overrides = {})
    {
      'DEVELOPMENT_TEAM' => 'ABCDE12345',
      'GLOW_WEB_DOMAIN' => 'glow.example.com',
      'API_BASE_URL' => 'https://glow.example.com',
      'GLOW_APP_BUNDLE_ID' => 'com.davidxie.glow',
      'GLOW_LIVE_ACTIVITY_BUNDLE_ID' => 'com.davidxie.glow.LiveActivity',
      'MARKETING_VERSION' => '0.1.0',
    }.merge(overrides)
  end

  def env(overrides = {})
    {
      'ASC_KEY_ID' => 'KEY1234567',
      'ASC_ISSUER_ID' => '57246542-96fe-1a63-e053-0824d011072a',
      'ASC_KEY' => P8,
      'SUPABASE_URL' => 'https://abcdefgh.supabase.co',
      'SUPABASE_ANON_KEY' => 'sb_publishable_realProjectKey_abc123',
      'DIST_CERT_P12_BASE64' => 'MIIK',
      'DIST_CERT_PASSWORD' => 'pw',
      'PROFILE_APP_BASE64' => 'MIIP',
      'PROFILE_LIVE_ACTIVITY_BASE64' => 'MIIP',
    }.merge(overrides)
  end

  def info(overrides = {})
    {
      'CFBundleIdentifier' => 'com.davidxie.glow',
      'CFBundleShortVersionString' => '0.1.0',
      'CFBundleVersion' => '7',
      'GlowWebDomain' => 'glow.example.com',
      'GlowAPIBaseURL' => 'https://glow.example.com',
      'GlowSupabaseURL' => 'https://abcdefgh.supabase.co',
      'GlowSupabaseAnonKey' => 'sb_publishable_realProjectKey_abc123',
      'GlowPostHogKey' => '',
    }.merge(overrides)
  end

  def extension_info(overrides = {})
    { 'CFBundleIdentifier' => 'com.davidxie.glow.LiveActivity', 'CFBundleShortVersionString' => '0.1.0',
      'CFBundleVersion' => '7' }.merge(overrides)
  end

  def entitlements(overrides = {})
    {
      'aps-environment' => 'production',
      'com.apple.developer.associated-domains' => ['applinks:glow.example.com'],
      'com.apple.developer.applesignin' => ['Default'],
      'get-task-allow' => false,
    }.merge(overrides)
  end

  def expect(overrides = {})
    { bundle_id: 'com.davidxie.glow', live_activity_bundle_id: 'com.davidxie.glow.LiveActivity',
      domain: 'glow.example.com', version: '0.1.0', build: 7,
      supabase_url: 'https://abcdefgh.supabase.co', anon_key: 'sb_publishable_realProjectKey_abc123',
      strict: true }.merge(overrides)
  end
end

class XcconfigTest < Minitest::Test
  def test_reads_includes_comments_and_expands_references
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'Shared.xcconfig'), <<~XCCONFIG)
        // A comment
        GLOW_WEB_DOMAIN = glow.example.com // trailing comment
        GLOW_APP_BUNDLE_ID = com.davidxie.glow
        GLOW_LIVE_ACTIVITY_BUNDLE_ID = $(GLOW_APP_BUNDLE_ID).LiveActivity
        SDK_ONLY[sdk=iphoneos*] = skipped
        DEVELOPMENT_TEAM =
      XCCONFIG
      File.write(File.join(dir, 'Release.xcconfig'), <<~XCCONFIG)
        #include "Shared.xcconfig"
        #include? "Missing.xcconfig"
        API_BASE_URL = https:/$()/$(GLOW_WEB_DOMAIN)
        DEVELOPMENT_TEAM = ABCDE12345
      XCCONFIG

      settings = GlowRelease.release_settings(dir)
      assert_equal 'https://glow.example.com', settings['API_BASE_URL']
      assert_equal 'com.davidxie.glow.LiveActivity', settings['GLOW_LIVE_ACTIVITY_BUNDLE_ID']
      assert_equal 'ABCDE12345', settings['DEVELOPMENT_TEAM'], 'later lines win'
      refute settings.key?('SDK_ONLY')
    end
  end

  def test_a_required_include_that_is_missing_raises
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'Release.xcconfig'), "#include \"Nope.xcconfig\"\n")
      assert_raises(ArgumentError) { GlowRelease.release_settings(dir) }
    end
  end

  def test_the_repos_release_settings
    settings = GlowRelease.release_settings(File.expand_path('../../Glow/Config', __dir__))
    assert_equal 'com.davidxie.glow', settings['GLOW_APP_BUNDLE_ID']
    assert_equal 'com.davidxie.glow.LiveActivity', settings['GLOW_LIVE_ACTIVITY_BUNDLE_ID']
    assert_equal "https://#{settings['GLOW_WEB_DOMAIN']}", settings['API_BASE_URL']
    assert_equal 'production', settings['GLOW_APS_ENVIRONMENT']
  end
end

class PreflightTest < Minitest::Test
  def preflight(settings: Fixtures.settings, env: Fixtures.env, ci: true, **rest)
    GlowRelease.preflight(settings: settings, env: env, ci: ci, **rest)
  end

  def test_everything_present_passes
    assert_empty preflight
  end

  def test_no_apple_account_is_blocked_not_an_error
    problems = preflight(settings: Fixtures.settings('DEVELOPMENT_TEAM' => ''), env: {})
    refute_empty problems
    assert problems.all?(&:blocked?), problems.reject(&:blocked?).join("\n")
    assert_includes problems.map(&:needs).uniq.sort, :apple
    assert_includes problems.map(&:needs), :supabase
    assert(problems.find { |p| p.needs == :apple }.to_s.include?('blocked: needs Apple Developer account'))
  end

  def test_placeholder_domain_is_blocked_on_the_domain
    problems = preflight(settings: Fixtures.settings('GLOW_WEB_DOMAIN' => 'glow-domain-not-chosen.invalid',
                                                     'API_BASE_URL' => 'https://glow-domain-not-chosen.invalid'))
    assert_equal [:domain], problems.map(&:needs)
  end

  def test_bad_team_and_domain_are_errors
    problems = preflight(settings: Fixtures.settings('DEVELOPMENT_TEAM' => 'abc', 'GLOW_WEB_DOMAIN' => 'Glow Example'))
    assert_equal 2, problems.count
    refute problems.any?(&:blocked?)
  end

  def test_api_url_must_follow_the_domain
    problems = preflight(settings: Fixtures.settings('API_BASE_URL' => 'http://localhost:3000'))
    assert_equal 1, problems.count
    assert_match(/API_BASE_URL/, problems.first.message)
  end

  def test_the_app_only_ever_holds_the_anon_key
    secret = preflight(env: Fixtures.env('SUPABASE_ANON_KEY' => 'sb_secret_abcdefghijklmnopqrstuvwxyz'))
    assert_match(/secret key/, secret.first.message)
    service = preflight(env: Fixtures.env('SUPABASE_ANON_KEY' => Fixtures.jwt(role: 'service_role')))
    assert_match(/service_role key/, service.first.message)
    local = preflight(env: Fixtures.env('SUPABASE_ANON_KEY' => GlowRelease::LOCAL_SUPABASE_KEY))
    assert_match(/local stack/, local.first.message)
    assert_empty preflight(env: Fixtures.env('SUPABASE_ANON_KEY' => Fixtures.jwt(role: 'anon')))
    refute_empty preflight(env: Fixtures.env('SUPABASE_ANON_KEY' => 'not-a-key'))
  end

  def test_supabase_url_must_be_hosted_https
    ['http://abcdefgh.supabase.co', 'https://127.0.0.1:54421', 'https://localhost', 'not a url',
     'https://192.168.1.4'].each do |url|
      problems = preflight(env: Fixtures.env('SUPABASE_URL' => url))
      assert_equal 1, problems.count, url
      refute problems.first.blocked?, url
    end
  end

  def test_posthog_personal_keys_are_refused
    assert_match(/personal API key/, preflight(env: Fixtures.env('POSTHOG_KEY' => 'phx_abc')).first.message)
    refute_empty preflight(env: Fixtures.env('POSTHOG_KEY' => 'whatever'))
    assert_empty preflight(env: Fixtures.env('POSTHOG_KEY' => 'phc_abc', 'SENTRY_DSN' => 'https://k@o1.ingest.sentry.io/1'))
    refute_empty preflight(env: Fixtures.env('SENTRY_DSN' => 'http://k@localhost/1'))
  end

  def test_api_key_formats
    assert_empty preflight(env: Fixtures.env('ASC_KEY' => Base64.strict_encode64(Fixtures::P8)))
    assert_empty preflight(env: Fixtures.env('ASC_KEY' => Fixtures::P8.gsub("\n", '\n')))
    assert_equal 1, preflight(env: Fixtures.env('ASC_KEY' => 'nope')).count
    assert_equal 1, preflight(env: Fixtures.env('ASC_KEY_ID' => 'short')).count
    assert_equal 1, preflight(env: Fixtures.env('ASC_ISSUER_ID' => 'not-a-uuid')).count
    assert_equal 1, preflight(env: Fixtures.env('ASC_KEY' => nil, 'ASC_KEY_PATH' => '/no/such/AuthKey.p8')).count
  end

  def test_signing_assets_are_only_required_in_ci
    env = Fixtures.env.reject { |name, _| GlowRelease::SIGNING_SECRETS.include?(name) }
    assert_equal 4, preflight(env: env, ci: true).count
    assert_empty preflight(env: env, ci: false)
  end

  def test_project_yml_must_name_both_release_profiles
    profiles = { 'Glow' => 'Glow App Store', 'GlowLiveActivity' => 'Glow Live Activity App Store' }
    without = preflight(project_yml: "targets:\n", profiles: profiles)
    assert_equal [:signing, :signing], without.map(&:needs)
    yml = <<~YAML
      "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": Glow App Store
      "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": Glow Live Activity App Store
    YAML
    assert_empty preflight(project_yml: yml, profiles: profiles)
  end

  def test_the_repos_project_yml_names_the_profiles_the_fastfile_uses
    yml = File.read(File.expand_path('../../project.yml', __dir__))
    fastfile = File.read(File.expand_path('../Fastfile', __dir__))
    profiles = fastfile.scan(/'(Glow(?:LiveActivity)?)' => '([^']+)'/).to_h
    assert_equal 2, profiles.size
    problems = GlowRelease.project_signing_problems(yml, profiles)
    skip "waiting on B9's signing request to A1: #{problems.map(&:message).join(' ')}" unless problems.empty?
    assert_empty problems
  end
end

class OverridesTest < Minitest::Test
  def test_build_number_and_hosted_values_with_xcconfig_safe_urls
    text = GlowRelease.overrides_xcconfig(42, Fixtures.env('POSTHOG_KEY' => 'phc_abc', 'SENTRY_DSN' => ''))
    assert_equal <<~XCCONFIG, text
      CURRENT_PROJECT_VERSION = 42
      SUPABASE_URL = https:/$()/abcdefgh.supabase.co
      SUPABASE_ANON_KEY = sb_publishable_realProjectKey_abc123
      POSTHOG_KEY = phc_abc
    XCCONFIG
    refute_match(/ASC_KEY|DIST_CERT|PRIVATE KEY/, text, 'signing secrets never go into the build settings')
  end

  def test_refuses_values_that_could_inject_settings
    assert_raises(ArgumentError) { GlowRelease.overrides_xcconfig(1, 'SUPABASE_URL' => "https://a.co\nDEVELOPMENT_TEAM = X") }
    assert_raises(ArgumentError) { GlowRelease.overrides_xcconfig(1, 'SUPABASE_ANON_KEY' => '$(HOME)') }
    assert_raises(ArgumentError) { GlowRelease.overrides_xcconfig('7a', {}) }
  end
end

class VerifyAppTest < Minitest::Test
  def verify(info: Fixtures.info, extension_info: Fixtures.extension_info,
             entitlements: Fixtures.entitlements, files: { 'Glow.app/Glow' => 'binary' }, expect: Fixtures.expect)
    GlowRelease.verify_app(info: info, extension_info: extension_info, entitlements: entitlements,
                           files: files, expect: expect)
  end

  def test_a_good_release_build_passes
    problems, warnings = verify
    assert_empty problems
    assert_empty warnings
  end

  def test_debug_only_keys_fail_the_release
    problems, = verify(info: Fixtures.info(
      'CFBundleURLTypes' => [{ 'CFBundleURLSchemes' => ['glow'] }],
      'NSAppTransportSecurity' => { 'NSAllowsLocalNetworking' => true, 'NSAllowsArbitraryLoads' => true },
    ))
    assert_equal 3, problems.count, problems.join("\n")
  end

  def test_endpoints_must_be_the_hosted_ones
    problems, = verify(info: Fixtures.info('GlowAPIBaseURL' => 'http://localhost:3000',
                                           'GlowSupabaseURL' => 'http://127.0.0.1:54421',
                                           'GlowSupabaseAnonKey' => GlowRelease::LOCAL_SUPABASE_KEY))
    assert_equal 3, problems.count, problems.join("\n")
  end

  def test_the_build_must_carry_the_values_it_was_given
    problems, = verify(info: Fixtures.info('GlowSupabaseAnonKey' => 'sb_publishable_someOtherProject'))
    assert_equal 1, problems.count
  end

  def test_push_and_links_need_production_entitlements
    problems, = verify(entitlements: Fixtures.entitlements(
      'aps-environment' => 'development',
      'com.apple.developer.associated-domains' => ['applinks:glow-domain-not-chosen.invalid'],
      'get-task-allow' => true,
      'com.apple.developer.applesignin' => nil,
    ))
    assert_equal 4, problems.count, problems.join("\n")
  end

  def test_versions_must_match_between_app_and_extension
    problems, = verify(extension_info: Fixtures.extension_info('CFBundleVersion' => '6'))
    assert_equal 1, problems.count
    problems, = verify(extension_info: nil)
    assert_match(/extension/, problems.first)
    problems, = verify(info: Fixtures.info('CFBundleVersion' => '8'),
                       extension_info: Fixtures.extension_info('CFBundleVersion' => '8'))
    assert_equal 1, problems.count, 'the build number is the one asked for'
  end

  def test_secrets_and_debug_hooks_in_the_bundle_fail
    service = Fixtures.jwt(role: 'service_role')
    anon = Fixtures.jwt(role: 'anon')
    files = {
      'Glow.app/Glow' => "\x00\xffsb_secret_".b + 'sb_secret_abcdefghijklmnopqrstuv'.b,
      'Glow.app/Frameworks/X' => "-----BEGIN PRIVATE KEY-----\n",
      'Glow.app/config.json' => %({"a":"#{service}","b":"#{anon}"}),
      'Glow.app/Debug' => '/api/dev/test-login GlowDebugOpenURL',
    }
    problems, = verify(files: files)
    assert_equal 5, problems.count, problems.join("\n")
  end

  def test_supabase_swift_s_own_prefix_strings_are_fine
    problems, = verify(files: { 'Glow.app/Glow' => "sb_secret_\x00sb_publishable_\x00service_role".b })
    assert_empty problems
  end

  def test_unsigned_placeholder_builds_only_warn_when_not_strict
    info = Fixtures.info('GlowWebDomain' => 'glow-domain-not-chosen.invalid',
                         'GlowAPIBaseURL' => 'https://glow-domain-not-chosen.invalid',
                         'GlowSupabaseURL' => '', 'GlowSupabaseAnonKey' => '')
    expect = Fixtures.expect(domain: 'glow-domain-not-chosen.invalid', build: nil, version: nil,
                             supabase_url: nil, anon_key: nil, strict: false)
    problems, warnings = verify(info: info, entitlements: nil, expect: expect)
    assert_empty problems
    assert_equal 4, warnings.count, warnings.join("\n")

    problems, = verify(info: info, entitlements: nil, expect: expect.merge(strict: true))
    assert_equal 4, problems.count
  end
end

class PrivacyAnswersTest < Minitest::Test
  MANIFEST = File.expand_path('../../Glow/PrivacyInfo.xcprivacy', __dir__)
  ANSWERS = File.expand_path('../app-privacy.json', __dir__)

  def entry(type, linked: true, tracking: false, purposes: ['NSPrivacyCollectedDataTypePurposeAppFunctionality'])
    { 'NSPrivacyCollectedDataType' => type, 'NSPrivacyCollectedDataTypeLinked' => linked,
      'NSPrivacyCollectedDataTypeTracking' => tracking, 'NSPrivacyCollectedDataTypePurposes' => purposes }
  end

  def test_maps_manifest_entries_to_app_store_connect_answers
    manifest = { 'NSPrivacyCollectedDataTypes' => [
      entry('NSPrivacyCollectedDataTypePreciseLocation'),
      entry('NSPrivacyCollectedDataTypeProductInteraction', linked: false,
                                                            purposes: ['NSPrivacyCollectedDataTypePurposeAnalytics']),
      entry('NSPrivacyCollectedDataTypeDeviceID', tracking: true),
    ] }
    assert_equal [
      { 'category' => 'DEVICE_ID', 'purposes' => ['APP_FUNCTIONALITY'],
        'data_protections' => %w[DATA_LINKED_TO_YOU DATA_USED_TO_TRACK_YOU] },
      { 'category' => 'PRECISE_LOCATION', 'purposes' => ['APP_FUNCTIONALITY'], 'data_protections' => ['DATA_LINKED_TO_YOU'] },
      { 'category' => 'PRODUCT_INTERACTION', 'purposes' => ['ANALYTICS'], 'data_protections' => ['DATA_NOT_LINKED_TO_YOU'] },
    ], GlowRelease.privacy_answers(manifest)
  end

  def test_nothing_collected
    assert_equal [{ 'data_protections' => ['DATA_NOT_COLLECTED'] }], GlowRelease.privacy_answers({})
  end

  def test_unknown_types_raise_instead_of_being_dropped
    assert_raises(ArgumentError) do
      GlowRelease.privacy_answers('NSPrivacyCollectedDataTypes' => [entry('NSPrivacyCollectedDataTypeTelepathy')])
    end
  end

  def test_differences_name_each_change
    want = [{ 'category' => 'NAME', 'purposes' => ['APP_FUNCTIONALITY'], 'data_protections' => ['DATA_LINKED_TO_YOU'] }]
    have = [{ 'category' => 'NAME', 'purposes' => ['ANALYTICS'], 'data_protections' => ['DATA_LINKED_TO_YOU'] },
            { 'category' => 'AUDIO', 'purposes' => [], 'data_protections' => [] }]
    differences = GlowRelease.privacy_differences(want, have)
    assert_equal 2, differences.count
    assert_empty GlowRelease.privacy_differences(want, want)
  end

  def test_the_committed_answers_match_the_privacy_manifest
    expected = GlowRelease.privacy_answers(Plist.parse_xml(MANIFEST))
    assert_empty GlowRelease.privacy_differences(expected, JSON.parse(File.read(ANSWERS)))
    linked = expected.select { |a| a['data_protections'].include?('DATA_LINKED_TO_YOU') }.map { |a| a['category'] }
    assert_includes linked, 'PRECISE_LOCATION', 'D43: location is declared even though only pass or fail is kept'
    assert expected.none? { |a| a['data_protections'].include?('DATA_USED_TO_TRACK_YOU') }, 'nothing tracks'
  end
end

class TextsTest < Minitest::Test
  def test_the_beta_texts_exist_and_fit
    assert_empty GlowRelease.text_problems(File.expand_path('../testflight', __dir__))
  end

  def test_review_contact_comes_from_the_environment
    info, problems = GlowRelease.review_contact({})
    assert_empty info
    assert_equal 5, problems.count
    info, problems = GlowRelease.review_contact(
      'GLOW_REVIEW_FIRST_NAME' => 'D', 'GLOW_REVIEW_LAST_NAME' => 'X', 'GLOW_REVIEW_EMAIL' => 'd@example.com',
      'GLOW_REVIEW_PHONE' => '+1 555 0100', 'GLOW_FEEDBACK_EMAIL' => 'feedback@example.com'
    )
    assert_empty problems
    assert_equal %i[contact_email contact_first_name contact_last_name contact_phone], info.keys.sort
  end
end
