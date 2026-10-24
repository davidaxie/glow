# Pure helpers for Glow's release lanes. Owner: B9. See docs/RELEASE.md.
#
# Everything here is plain Ruby with no fastlane calls, so ios/fastlane/test can check it on any
# machine. The Fastfile gathers the inputs (files, environment, the built app) and acts on the
# results.
require 'base64'
require 'json'
require 'uri'

module GlowRelease
  # ios/fastlane, as an absolute path.
  DIR = __dir__

  module_function

  # ---------------------------------------------------------------------------------------------
  # xcconfig

  # Reads `KEY = value` lines from an xcconfig and the files it includes, later lines winning.
  # Conditional settings (`KEY[sdk=...]`) are skipped: nothing the lanes read uses them.
  def read_xcconfig(path, into = {})
    File.foreach(path) do |raw|
      line = raw.sub(%r{//.*\z}m, '').strip
      next if line.empty?

      if (m = line.match(/\A#include(\?)?\s+"([^"]+)"/))
        included = File.expand_path(m[2], File.dirname(path))
        if File.exist?(included)
          read_xcconfig(included, into)
        elsif m[1].nil?
          raise ArgumentError, "#{path} includes #{m[2]}, which doesn't exist"
        end
        next
      end
      next unless (m = line.match(/\A([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/))

      into[m[1]] = m[2].strip
    end
    into
  end

  # Expands $(NAME) and ${NAME} the way Xcode does for the simple cases our xcconfigs use.
  # `$()` is the empty string (it's how the xcconfigs write `//` in URLs).
  def expand(value, settings, depth = 0)
    raise ArgumentError, "build setting reference loop in #{value}" if depth > 10

    value.gsub(/\$[({]([A-Za-z0-9_]*)[)}]/) do
      name = Regexp.last_match(1)
      name.empty? ? '' : expand(settings.fetch(name, ''), settings, depth + 1)
    end
  end

  # The Release configuration's settings from ios/Glow/Config, fully expanded.
  def release_settings(config_dir)
    raw = read_xcconfig(File.join(config_dir, 'Release.xcconfig'))
    raw.to_h { |key, value| [key, expand(value, raw)] }
  end

  # ---------------------------------------------------------------------------------------------
  # What `beta` needs

  # One thing that stops a release. `needs` says what unblocks it:
  #   :apple    the paid Apple Developer account and what David makes with it
  #   :supabase the hosted Supabase project
  #   :domain   the web domain
  #   :signing  the signing change in ios/project.yml (B9's cross-owner request to A1)
  #   nil       a mistake to fix now
  Problem = Struct.new(:message, :needs) do
    def blocked?
      !needs.nil?
    end

    def to_s
      blocked? ? "#{message} (blocked: #{GlowRelease::NEEDS.fetch(needs)})" : message
    end
  end

  NEEDS = {
    apple: 'needs Apple Developer account',
    supabase: 'needs the hosted Supabase project',
    domain: 'needs the web domain',
    signing: "needs the signing settings in ios/project.yml (B9's request to A1)",
  }.freeze

  TEAM_ID = /\A[A-Z0-9]{10}\z/
  HOSTNAME = /\A(?=.{1,253}\z)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/
  ISSUER_ID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  PLACEHOLDER_DOMAIN_TLD = '.invalid'
  # The local stack's public demo key (ios/Glow/Config/Debug.xcconfig). It only works against
  # 127.0.0.1, so a Release build carrying it is a mistake.
  LOCAL_SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'

  # Signing assets CI needs. Locally they can live in the login keychain instead.
  SIGNING_SECRETS = %w[DIST_CERT_P12_BASE64 DIST_CERT_PASSWORD PROFILE_APP_BASE64
                       PROFILE_LIVE_ACTIVITY_BASE64].freeze

  # Everything `beta` checks before it builds. `env` is ENV or a hash; `ci` means no keychain to
  # fall back on, so the signing assets must come from the environment.
  def preflight(settings:, env:, ci:, project_yml: nil, profiles: {})
    problems = []
    problems.concat(team_problems(settings))
    problems.concat(domain_problems(settings))
    problems.concat(api_key_problems(env))
    problems.concat(supabase_problems(env))
    problems.concat(analytics_problems(env))
    problems.concat(signing_problems(env, ci: ci))
    problems.concat(project_signing_problems(project_yml, profiles)) if project_yml
    problems
  end

  def team_problems(settings)
    team = settings['DEVELOPMENT_TEAM'].to_s
    if team.empty?
      [Problem.new('DEVELOPMENT_TEAM in ios/Glow/Config/Shared.xcconfig is empty. Set it to the ' \
                   '10-character Team ID (developer.apple.com, Membership details).', :apple)]
    elsif !team.match?(TEAM_ID)
      [Problem.new("DEVELOPMENT_TEAM (#{team}) isn't a 10-character Team ID.", nil)]
    else
      []
    end
  end

  def domain_problems(settings)
    domain = settings['GLOW_WEB_DOMAIN'].to_s
    if domain.empty? || domain.end_with?(PLACEHOLDER_DOMAIN_TLD)
      [Problem.new("GLOW_WEB_DOMAIN in ios/Glow/Config/Shared.xcconfig is still the placeholder " \
                   "(#{domain.empty? ? 'empty' : domain}). Release builds talk to https://{DOMAIN}.",
                   :domain)]
    elsif !domain.match?(HOSTNAME)
      [Problem.new("GLOW_WEB_DOMAIN (#{domain}) isn't a lowercase host name like glow.example.com.",
                   nil)]
    elsif settings['API_BASE_URL'] != "https://#{domain}"
      [Problem.new("Release API_BASE_URL is #{settings['API_BASE_URL'].inspect}, not https://#{domain}.",
                   nil)]
    else
      []
    end
  end

  def api_key_problems(env)
    problems = []
    key_id = env['ASC_KEY_ID'].to_s.strip
    issuer = env['ASC_ISSUER_ID'].to_s.strip
    key = env['ASC_KEY'].to_s
    key_path = env['ASC_KEY_PATH'].to_s

    problems << missing('ASC_KEY_ID', 'the App Store Connect API key ID', :apple) if key_id.empty?
    problems << missing('ASC_ISSUER_ID', 'the API key issuer ID', :apple) if issuer.empty?
    if key.strip.empty? && key_path.empty?
      problems << missing('ASC_KEY', 'the API key (.p8) contents, or ASC_KEY_PATH', :apple)
    end
    if !key_id.empty? && !key_id.match?(TEAM_ID)
      problems << Problem.new("ASC_KEY_ID isn't a 10-character key ID.", nil)
    end
    if !issuer.empty? && !issuer.match?(ISSUER_ID)
      problems << Problem.new("ASC_ISSUER_ID isn't a UUID like 57246542-96fe-1a63-e053-0824d011072a.",
                              nil)
    end
    if !key.strip.empty? && p8_content(key).nil?
      problems << Problem.new('ASC_KEY is neither the .p8 file contents nor base64 of them.', nil)
    end
    if !key_path.empty? && !File.file?(key_path)
      problems << Problem.new("ASC_KEY_PATH (#{key_path}) isn't a file.", nil)
    end
    problems
  end

  def supabase_problems(env)
    problems = []
    url = env['SUPABASE_URL'].to_s.strip
    key = env['SUPABASE_ANON_KEY'].to_s.strip

    if url.empty?
      problems << missing('SUPABASE_URL', "the hosted project's URL", :supabase)
    elsif (reason = hosted_url_problem(url))
      problems << Problem.new("SUPABASE_URL #{reason}.", nil)
    end

    if key.empty?
      problems << missing('SUPABASE_ANON_KEY', "the hosted project's anon (publishable) key",
                          :supabase)
    elsif (reason = anon_key_problem(key))
      problems << Problem.new("SUPABASE_ANON_KEY #{reason}. The app only ever holds the anon key.",
                              nil)
    end
    problems
  end

  def analytics_problems(env)
    problems = []
    posthog = env['POSTHOG_KEY'].to_s.strip
    sentry = env['SENTRY_DSN'].to_s.strip
    unless posthog.empty?
      if posthog.start_with?('phx_')
        problems << Problem.new('POSTHOG_KEY is a PostHog personal API key (phx_), which is a ' \
                                "secret. Use the project's public key (phc_).", nil)
      elsif !posthog.start_with?('phc_')
        problems << Problem.new("POSTHOG_KEY isn't a PostHog project key (phc_...).", nil)
      end
    end
    if !sentry.empty? && (reason = hosted_url_problem(sentry))
      problems << Problem.new("SENTRY_DSN #{reason}.", nil)
    end
    problems
  end

  def signing_problems(env, ci:)
    return [] unless ci

    SIGNING_SECRETS.select { |name| env[name].to_s.strip.empty? }.map do |name|
      missing(name, SIGNING_SECRET_HELP.fetch(name), :apple)
    end
  end

  SIGNING_SECRET_HELP = {
    'DIST_CERT_P12_BASE64' => 'base64 of the Apple Distribution certificate (.p12)',
    'DIST_CERT_PASSWORD' => "the .p12's password",
    'PROFILE_APP_BASE64' => 'base64 of the "Glow App Store" provisioning profile',
    'PROFILE_LIVE_ACTIVITY_BASE64' => 'base64 of the "Glow Live Activity App Store" profile',
  }.freeze

  # The Release signing settings B9 asked A1 for in ios/project.yml (see docs/RELEASE.md). Until
  # they're merged, archives would sign with the development profile, which can't ship.
  def project_signing_problems(project_yml, profiles)
    profiles.filter_map do |target, profile|
      next if project_yml.include?("PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]\": #{profile}")

      Problem.new("ios/project.yml doesn't give #{target} the \"#{profile}\" profile for Release.",
                  :signing)
    end
  end

  def missing(name, what, needs)
    Problem.new("#{name} isn't set: #{what}.", needs)
  end

  # Why a URL can't be a hosted endpoint, or nil if it can.
  def hosted_url_problem(value)
    uri = URI.parse(value)
    return 'must be an https URL' unless uri.is_a?(URI::HTTPS) && uri.host.to_s != ''
    return "points at this computer (#{uri.host})" if local_host?(uri.host)

    nil
  rescue URI::InvalidURIError
    'must be an https URL'
  end

  def local_host?(host)
    host = host.to_s.downcase.delete_prefix('[').delete_suffix(']')
    host == 'localhost' || host.end_with?('.localhost') || host.end_with?('.local') ||
      host.match?(/\A127\./) || host == '::1' || host == '0.0.0.0' ||
      host.match?(/\A(10|192\.168)\./) || host.match?(/\A172\.(1[6-9]|2\d|3[01])\./)
  end

  # Why a key can't go in the app as the Supabase anon key, or nil if it can.
  def anon_key_problem(key)
    return 'is the local stack\'s demo key' if key == LOCAL_SUPABASE_KEY
    return 'is a secret key (sb_secret_)' if key.start_with?('sb_secret_')
    return nil if key.start_with?('sb_publishable_')

    role = jwt_role(key)
    return "isn't a Supabase anon key (sb_publishable_... or a JWT with role anon)" if role.nil?
    return "is the #{role} key" unless role == 'anon'

    nil
  end

  # The `role` claim of a Supabase JWT key, or nil if it isn't one.
  def jwt_role(token)
    parts = token.split('.')
    return nil unless parts.length == 3

    JSON.parse(Base64.urlsafe_decode64(pad64(parts[1])))['role']
  rescue ArgumentError, JSON::ParserError, TypeError, NoMethodError
    nil
  end

  def pad64(value)
    value + ('=' * ((4 - (value.length % 4)) % 4))
  end

  # ASC_KEY may be the .p8 file's contents or base64 of them (GitHub secrets keep either).
  # Returns the PEM text, or nil if it's neither.
  def p8_content(value)
    text = value.to_s.strip
    text = text.gsub('\n', "\n") # a one-line paste with literal \n
    return text if pem_private_key?(text)

    decoded = Base64.decode64(text).strip
    pem_private_key?(decoded) ? decoded : nil
  end

  def pem_private_key?(text)
    text.start_with?('-----BEGIN PRIVATE KEY-----') && text.end_with?('-----END PRIVATE KEY-----')
  end

  # ---------------------------------------------------------------------------------------------
  # Build overrides

  # Values from the environment that the Release build needs but git doesn't hold.
  OVERRIDES = %w[SUPABASE_URL SUPABASE_ANON_KEY POSTHOG_KEY SENTRY_DSN].freeze

  # The xcconfig `beta` hands xcodebuild with -xcconfig: the build number plus OVERRIDES. It
  # outranks every other setting, for the app and the extension alike. In xcconfig files `//`
  # starts a comment, so URLs are written as https:/$()/host.
  def overrides_xcconfig(build, env)
    values = { 'CURRENT_PROJECT_VERSION' => Integer(build.to_s, 10).to_s }
    OVERRIDES.each do |name|
      value = env[name].to_s.strip
      next if value.empty?
      raise ArgumentError, "#{name} must be one line, without $( or ;" if value.match?(/[\n;]|\$\(/)

      values[name] = value
    end
    values.map { |key, value| "#{key} = #{value.gsub('//', '/$()/')}\n" }.join
  end

  # ---------------------------------------------------------------------------------------------
  # The built app

  # What a Release build must never carry. Each is [label, pattern]. Plain prefixes like
  # "sb_secret_" appear in supabase-swift itself, so the patterns need a real key's body.
  FORBIDDEN_CONTENT = [
    ['a Supabase secret key', /sb_secret_[A-Za-z0-9_-]{16,}/],
    ['a private key', /-----BEGIN (?:EC |RSA |ENCRYPTED )?PRIVATE KEY-----/],
    ['an Anthropic API key', /sk-ant-[A-Za-z0-9_-]{20,}/],
    ['a PostHog personal API key', /phx_[A-Za-z0-9]{20,}/],
    ["the local stack's demo key", Regexp.new(Regexp.escape(LOCAL_SUPABASE_KEY))],
    ['the Debug-only test sign-in route', %r{/api/dev/test-login}],
    ['a Debug-only launch argument', /GlowDebug[A-Z][A-Za-z]+/],
  ].freeze

  JWT_PATTERN = /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/

  # Checks a built Glow.app. `info` and `extension_info` are the parsed Info.plists, `entitlements`
  # the signed entitlements (nil for an unsigned build), `files` a hash of relative path => bytes.
  # `expect` has :bundle_id, :live_activity_bundle_id, :domain, :version, :build (nil to skip),
  # :supabase_url, :anon_key and :strict. When strict is false (the unsigned check on PRs), values
  # that only exist once the accounts do are warnings instead of problems.
  # Returns [problems, warnings], each a list of sentences.
  def verify_app(info:, extension_info:, entitlements:, files:, expect:)
    problems = []
    warnings = []
    soft = expect[:strict] ? problems : warnings

    check_identity(info, extension_info, expect, problems)
    check_debug_only_keys(info, problems)
    check_endpoints(info, expect, problems, soft)
    check_entitlements(entitlements, expect, problems, soft)
    check_contents(files, problems)
    [problems, warnings]
  end

  def check_identity(info, extension_info, expect, problems)
    if info['CFBundleIdentifier'] != expect[:bundle_id]
      problems << "The app's bundle ID is #{info['CFBundleIdentifier'].inspect}, not #{expect[:bundle_id]}."
    end
    if expect[:build] && info['CFBundleVersion'] != expect[:build].to_s
      problems << "The build number is #{info['CFBundleVersion'].inspect}, not #{expect[:build]}."
    end
    if expect[:version] && info['CFBundleShortVersionString'] != expect[:version]
      problems << "The version is #{info['CFBundleShortVersionString'].inspect}, not #{expect[:version]}."
    end
    if extension_info.nil?
      problems << 'The Live Activity extension (PlugIns/GlowLiveActivity.appex) is missing.'
      return
    end
    if extension_info['CFBundleIdentifier'] != expect[:live_activity_bundle_id]
      problems << "The Live Activity's bundle ID is #{extension_info['CFBundleIdentifier'].inspect}, " \
                  "not #{expect[:live_activity_bundle_id]}."
    end
    %w[CFBundleVersion CFBundleShortVersionString].each do |key|
      next if extension_info[key] == info[key]

      problems << "The Live Activity's #{key} (#{extension_info[key].inspect}) doesn't match the " \
                  "app's (#{info[key].inspect}). App Store Connect rejects that."
    end
  end

  # D34: the glow:// scheme and local networking exist in Debug builds only.
  def check_debug_only_keys(info, problems)
    schemes = Array(info['CFBundleURLTypes']).flat_map { |t| Array(t['CFBundleURLSchemes']) }
    if schemes.include?('glow')
      problems << 'The Debug-only glow:// link scheme is in the Release Info.plist (D34).'
    end
    ats = info['NSAppTransportSecurity'] || {}
    %w[NSAllowsLocalNetworking NSAllowsArbitraryLoads NSAllowsArbitraryLoadsInWebContent
       NSAllowsArbitraryLoadsForMedia NSExceptionDomains].each do |key|
      problems << "NSAppTransportSecurity has #{key} in Release (D34)." if ats.key?(key)
    end
  end

  def check_endpoints(info, expect, problems, soft)
    domain = expect[:domain].to_s
    api = info['GlowAPIBaseURL'].to_s
    if info['GlowWebDomain'] != domain
      problems << "GlowWebDomain is #{info['GlowWebDomain'].inspect}, not #{domain}."
    end
    if api != "https://#{domain}"
      problems << "GlowAPIBaseURL is #{api.inspect}, not https://#{domain}."
    end
    if domain.end_with?(PLACEHOLDER_DOMAIN_TLD)
      soft << "The web domain is still the placeholder (#{domain})."
    end

    supabase = info['GlowSupabaseURL'].to_s
    if supabase.empty?
      soft << 'GlowSupabaseURL is empty.'
    elsif (reason = hosted_url_problem(supabase))
      problems << "GlowSupabaseURL #{reason}."
    elsif expect[:supabase_url] && supabase != expect[:supabase_url]
      problems << "GlowSupabaseURL isn't the SUPABASE_URL this build was given."
    end

    anon = info['GlowSupabaseAnonKey'].to_s
    if anon.empty?
      soft << 'GlowSupabaseAnonKey is empty.'
    elsif (reason = anon_key_problem(anon))
      problems << "GlowSupabaseAnonKey #{reason}."
    elsif expect[:anon_key] && anon != expect[:anon_key]
      problems << "GlowSupabaseAnonKey isn't the SUPABASE_ANON_KEY this build was given."
    end

    posthog = info['GlowPostHogKey'].to_s
    if posthog.start_with?('phx_')
      problems << 'GlowPostHogKey is a PostHog personal API key, which is a secret.'
    end
  end

  def check_entitlements(entitlements, expect, problems, soft)
    if entitlements.nil?
      soft << "The build isn't signed, so its entitlements weren't checked."
      return
    end
    if entitlements['aps-environment'] != 'production'
      problems << "aps-environment is #{entitlements['aps-environment'].inspect}, not production, " \
                  'so TestFlight pushes would fail.'
    end
    domains = Array(entitlements['com.apple.developer.associated-domains'])
    if domains != ["applinks:#{expect[:domain]}"]
      problems << "Associated Domains are #{domains.inspect}, not [\"applinks:#{expect[:domain]}\"]."
    end
    if entitlements['get-task-allow'] == true
      problems << 'get-task-allow is on: this is a development-signed build.'
    end
    unless Array(entitlements['com.apple.developer.applesignin']).include?('Default')
      problems << 'Sign in with Apple is missing from the entitlements.'
    end
  end

  def check_contents(files, problems)
    files.each do |path, bytes|
      text = bytes.dup.force_encoding(Encoding::BINARY)
      FORBIDDEN_CONTENT.each do |label, pattern|
        binary = Regexp.new(pattern.source.b, pattern.options | Regexp::NOENCODING)
        problems << "#{path} contains #{label}." if text.match?(binary)
      end
      text.scan(Regexp.new(JWT_PATTERN.source.b, Regexp::NOENCODING)).uniq.each do |token|
        role = jwt_role(token)
        next if role.nil? || role == 'anon'

        problems << "#{path} contains a Supabase #{role} key."
      end
    end
  end

  # ---------------------------------------------------------------------------------------------
  # App Privacy answers

  # Privacy manifest data types to App Store Connect's App Privacy categories.
  CATEGORIES = {
    'NSPrivacyCollectedDataTypeName' => 'NAME',
    'NSPrivacyCollectedDataTypeEmailAddress' => 'EMAIL_ADDRESS',
    'NSPrivacyCollectedDataTypePhoneNumber' => 'PHONE_NUMBER',
    'NSPrivacyCollectedDataTypePhysicalAddress' => 'PHYSICAL_ADDRESS',
    'NSPrivacyCollectedDataTypeOtherUserContactInfo' => 'OTHER_CONTACT_INFO',
    'NSPrivacyCollectedDataTypeHealth' => 'HEALTH',
    'NSPrivacyCollectedDataTypeFitness' => 'FITNESS',
    'NSPrivacyCollectedDataTypePaymentInfo' => 'PAYMENT_INFORMATION',
    'NSPrivacyCollectedDataTypeCreditInfo' => 'CREDIT_AND_FRAUD',
    'NSPrivacyCollectedDataTypeOtherFinancialInfo' => 'OTHER_FINANCIAL_INFO',
    'NSPrivacyCollectedDataTypePreciseLocation' => 'PRECISE_LOCATION',
    'NSPrivacyCollectedDataTypeCoarseLocation' => 'COARSE_LOCATION',
    'NSPrivacyCollectedDataTypeSensitiveInfo' => 'SENSITIVE_INFO',
    'NSPrivacyCollectedDataTypeContacts' => 'CONTACTS',
    'NSPrivacyCollectedDataTypeEmailsOrTextMessages' => 'EMAILS_OR_TEXT_MESSAGES',
    'NSPrivacyCollectedDataTypePhotosorVideos' => 'PHOTOS_OR_VIDEOS',
    'NSPrivacyCollectedDataTypeAudioData' => 'AUDIO',
    'NSPrivacyCollectedDataTypeGameplayContent' => 'GAMEPLAY_CONTENT',
    'NSPrivacyCollectedDataTypeCustomerSupport' => 'CUSTOMER_SUPPORT',
    'NSPrivacyCollectedDataTypeOtherUserContent' => 'OTHER_USER_CONTENT',
    'NSPrivacyCollectedDataTypeBrowsingHistory' => 'BROWSING_HISTORY',
    'NSPrivacyCollectedDataTypeSearchHistory' => 'SEARCH_HISTORY',
    'NSPrivacyCollectedDataTypeUserID' => 'USER_ID',
    'NSPrivacyCollectedDataTypeDeviceID' => 'DEVICE_ID',
    'NSPrivacyCollectedDataTypePurchaseHistory' => 'PURCHASE_HISTORY',
    'NSPrivacyCollectedDataTypeProductInteraction' => 'PRODUCT_INTERACTION',
    'NSPrivacyCollectedDataTypeAdvertisingData' => 'ADVERTISING_DATA',
    'NSPrivacyCollectedDataTypeOtherUsageData' => 'OTHER_USAGE_DATA',
    'NSPrivacyCollectedDataTypeCrashData' => 'CRASH_DATA',
    'NSPrivacyCollectedDataTypePerformanceData' => 'PERFORMANCE_DATA',
    'NSPrivacyCollectedDataTypeOtherDiagnosticData' => 'OTHER_DIAGNOSTIC_DATA',
    'NSPrivacyCollectedDataTypeOtherDataTypes' => 'OTHER_DATA',
  }.freeze

  PURPOSES = {
    'NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising' => 'THIRD_PARTY_ADVERTISING',
    'NSPrivacyCollectedDataTypePurposeDeveloperAdvertising' => 'DEVELOPERS_ADVERTISING',
    'NSPrivacyCollectedDataTypePurposeAnalytics' => 'ANALYTICS',
    'NSPrivacyCollectedDataTypePurposeProductPersonalization' => 'PRODUCT_PERSONALIZATION',
    'NSPrivacyCollectedDataTypePurposeAppFunctionality' => 'APP_FUNCTIONALITY',
    'NSPrivacyCollectedDataTypePurposeOther' => 'OTHER_PURPOSES',
  }.freeze

  # The App Privacy answers a privacy manifest implies, in the JSON format fastlane's
  # upload_app_privacy_details_to_app_store reads. `manifest` is the parsed PrivacyInfo.xcprivacy.
  def privacy_answers(manifest)
    collected = Array(manifest['NSPrivacyCollectedDataTypes'])
    return [{ 'data_protections' => ['DATA_NOT_COLLECTED'] }] if collected.empty?

    by_category = {}
    collected.each do |entry|
      type = entry['NSPrivacyCollectedDataType']
      category = CATEGORIES.fetch(type) { raise ArgumentError, "unknown data type #{type}" }
      purposes = Array(entry['NSPrivacyCollectedDataTypePurposes']).map do |purpose|
        PURPOSES.fetch(purpose) { raise ArgumentError, "unknown purpose #{purpose}" }
      end
      protections = [entry['NSPrivacyCollectedDataTypeLinked'] ? 'DATA_LINKED_TO_YOU' : 'DATA_NOT_LINKED_TO_YOU']
      protections << 'DATA_USED_TO_TRACK_YOU' if entry['NSPrivacyCollectedDataTypeTracking']

      answer = by_category[category] ||= { 'category' => category, 'purposes' => [],
                                           'data_protections' => [] }
      answer['purposes'] |= purposes
      answer['data_protections'] |= protections
    end
    by_category.values.map do |answer|
      answer.merge('purposes' => answer['purposes'].sort,
                   'data_protections' => answer['data_protections'].sort)
    end.sort_by { |answer| answer['category'] }
  end

  # Sentences for every way the committed answers differ from what the manifest implies.
  def privacy_differences(expected, actual)
    index = ->(list) { list.to_h { |a| [a['category'] || 'NOT_COLLECTED', a] } }
    want = index.call(expected)
    have = index.call(actual)
    problems = []
    (want.keys - have.keys).each { |c| problems << "#{c} is in the privacy manifest but not in the answers." }
    (have.keys - want.keys).each { |c| problems << "#{c} is in the answers but not in the privacy manifest." }
    (want.keys & have.keys).each do |category|
      %w[purposes data_protections].each do |field|
        next if want[category][field].to_a.sort == have[category][field].to_a.sort

        problems << "#{category} #{field}: the manifest says #{want[category][field].inspect}, " \
                    "the answers say #{have[category][field].inspect}."
      end
    end
    problems
  end

  # ---------------------------------------------------------------------------------------------
  # Beta test information

  # App Store Connect's limits for TestFlight text fields.
  TEXT_LIMITS = {
    'description.txt' => 4000, # Beta App Description
    'what-to-test.txt' => 4000, # What to Test
    'review-notes.txt' => 4000, # Beta App Review notes
  }.freeze

  def text_problems(dir)
    TEXT_LIMITS.flat_map do |name, limit|
      path = File.join(dir, name)
      next ["ios/fastlane/testflight/#{name} is missing."] unless File.file?(path)

      text = File.read(path).strip
      problems = []
      problems << "ios/fastlane/testflight/#{name} is empty." if text.empty?
      if text.length > limit
        problems << "ios/fastlane/testflight/#{name} is #{text.length} characters; the limit is #{limit}."
      end
      problems
    end
  end

  # Beta App Review needs a contact Apple can reach. It's David's, so it comes from the
  # environment (GitHub secrets in CI) and never from git. Returns [info, problems].
  REVIEW_CONTACT = {
    'GLOW_REVIEW_FIRST_NAME' => :contact_first_name,
    'GLOW_REVIEW_LAST_NAME' => :contact_last_name,
    'GLOW_REVIEW_EMAIL' => :contact_email,
    'GLOW_REVIEW_PHONE' => :contact_phone,
  }.freeze

  def review_contact(env)
    info = {}
    problems = []
    REVIEW_CONTACT.each do |name, field|
      value = env[name].to_s.strip
      if value.empty?
        problems << missing(name, "the Beta App Review contact's #{field.to_s.delete_prefix('contact_').tr('_', ' ')}", :apple)
      else
        info[field] = value
      end
    end
    feedback = env['GLOW_FEEDBACK_EMAIL'].to_s.strip
    if feedback.empty?
      problems << missing('GLOW_FEEDBACK_EMAIL', 'where TestFlight feedback goes', :apple)
    end
    [info, problems]
  end
end
