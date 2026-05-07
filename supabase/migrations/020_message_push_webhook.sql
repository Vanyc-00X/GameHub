-- Database Webhook: Message INSERT -> Edge Function send-message-push.
-- В Supabase Database Webhooks используется функция supabase_functions.http_request.

do $$
begin
  if to_regclass('public."Message"') is null then
    return;
  end if;

  if to_regprocedure(
    'supabase_functions.http_request(text,text,jsonb,jsonb,integer)'
  ) is null then
    raise notice 'supabase_functions.http_request is not available; create the webhook in Supabase Dashboard after deploying the function.';
    return;
  end if;

  drop trigger if exists trg_message_push_webhook on public."Message";

  create trigger trg_message_push_webhook
    after insert on public."Message"
    for each row
    execute function supabase_functions.http_request(
      'https://tvjggbkxmgbdtcfxggza.supabase.co/functions/v1/send-message-push',
      'POST',
      '{"Content-Type":"application/json"}',
      '{}',
      '5000'
    );
end $$;
