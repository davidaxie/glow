-- 0003_b8_forget_account.sql · B8 · What account deletion and purge also clean up
--
-- Asked of A2 in docs/HANDOFFS.md (For A2, from B8). Adds functions only; no tables change.
--
-- Supabase Auth keeps its own audit log (auth.audit_log_entries): sign-ups, sign-ins and
-- deletions, with the person's user ID, email address and IP address. Deleting the auth user
-- doesn't touch it, and the deletion itself writes one more entry naming them. So after
-- DELETE /api/me the server calls forget_account_traces() to remove those entries (and any
-- Realtime message stored on the person's own topic), and the purge cron calls
-- purge_auth_audit() so nobody's sign-in history (and IP) piles up forever.

-- forget_account_traces: everything outside public that still names a deleted person.
-- Call it after the auth user is gone. Refuses a person who still exists.
-- Returns { auditEntries, realtimeMessages } (counts deleted).
create function public.forget_account_traces(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_audit    integer := 0;
  v_realtime integer := 0;
begin
  if p_user_id is null then
    perform private.raise_error('invalid_input');
  end if;
  if exists (select 1 from auth.users where id = p_user_id) then
    perform private.raise_error('invalid_input');
  end if;

  delete from auth.audit_log_entries a
   where a.payload ->> 'actor_id' = p_user_id::text
      or a.payload -> 'traits' ->> 'user_id' = p_user_id::text;
  get diagnostics v_audit = row_count;

  delete from realtime.messages m
   where m.topic = 'user:' || p_user_id::text;
  get diagnostics v_realtime = row_count;

  return jsonb_build_object('auditEntries', v_audit, 'realtimeMessages', v_realtime);
end;
$$;

-- purge_auth_audit: Auth audit entries older than p_older_than (the server passes 7 days).
-- Returns how many were deleted.
create function public.purge_auth_audit(p_older_than interval)
returns integer
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_older_than is null or p_older_than < interval '1 hour' then
    perform private.raise_error('invalid_input');
  end if;
  delete from auth.audit_log_entries where created_at < now() - p_older_than;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.forget_account_traces(uuid) from public, anon, authenticated;
revoke all on function public.purge_auth_audit(interval) from public, anon, authenticated;
grant execute on function public.forget_account_traces(uuid) to service_role;
grant execute on function public.purge_auth_audit(interval) to service_role;
