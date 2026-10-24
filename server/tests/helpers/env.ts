/** A valid local env, matching a default `supabase start`. Test values only. */
export const LOCAL_ENV = {
  SUPABASE_URL: 'http://127.0.0.1:54421',
  SUPABASE_ANON_KEY: 'sb_publishable_test_anon_key_0000000000',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test_service_key_00000000000',
  JOIN_TICKET_SECRET: 'test-join-ticket-secret-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  CARD_URL_SECRET: 'test-card-url-secret-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  CRON_SECRET: 'test-cron-secret-cccccccccccccccccccccccccccc',
} as const;

/** What a correctly set up Vercel production deploy looks like. Test values only. */
export const PRODUCTION_ENV = {
  VERCEL: '1',
  VERCEL_ENV: 'production',
  SUPABASE_URL: 'https://abcdefghijklmnop.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_prod_like_test_value_000',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_prod_like_test_value_0000000',
  JOIN_TICKET_SECRET: 'Zm9vYmFyYmF6cXV4cXV1eGNvcmdlZ3JhdWx0Z2FycGx5d2FsZG8x',
  CARD_URL_SECRET: 'cGxvdWdoZnJlZHdhbGRvcGx1Z2h0aHVkZ3JhdWx0Z2FycGx5d2Fs',
  CRON_SECRET: 'Y3JvbnRlc3RzZWNyZXRmb3J0aGVwdXJnZWpvYm9ubHlvbmUx',
  ANTHROPIC_API_KEY: 'sk-ant-test-0000000000000000000000',
  UPSTASH_REDIS_REST_URL: 'https://example-upstash.upstash.io',
  UPSTASH_REDIS_REST_TOKEN: 'upstash-test-token-000000000000',
  APNS_KEY_ID: 'ABC123DEFG',
  APNS_TEAM_ID: 'TEAM123456',
  APNS_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\\nTESTKEYTESTKEY\\n-----END PRIVATE KEY-----',
  APNS_BUNDLE_ID: 'com.davidxie.glow',
} as const;
