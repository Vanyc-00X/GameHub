-- Message INSERT -> Edge Function send-message-push через pg_net.
-- Это fallback вместо Dashboard Database Webhooks.

create extension if not exists pg_net;

create or replace function public._send_message_push_webhook()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
begin
  perform net.http_post(
    url := 'https://tvjggbkxmgbdtcfxggza.supabase.co/functions/v1/send-message-push',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('record', to_jsonb(new)),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists trg_message_push_pg_net on public."Message";
create trigger trg_message_push_pg_net
  after insert on public."Message"
  for each row
  execute function public._send_message_push_webhook();
