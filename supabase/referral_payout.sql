-- Vocation SL — where referral rewards are paid (run after referrals.sql). Safe to re-run.
-- Each referrer can save one Mobile Money account. Only they and admins can read it.

alter table public.referral_codes add column if not exists payout_provider   text not null default '';
alter table public.referral_codes add column if not exists payout_number     text not null default '';
alter table public.referral_codes add column if not exists payout_name       text not null default '';
alter table public.referral_codes add column if not exists payout_updated_at timestamptz;

create or replace function public.save_referral_payout(p_provider text, p_number text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  digits text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
begin
  if uid is null then raise exception 'Please sign in again.'; end if;
  if p_provider not in ('orange', 'africell') then raise exception 'Choose Orange Money or Africell Money.'; end if;
  -- Sierra Leone numbers: 0XX XXX XXX, 232 XX XXX XXX or XX XXX XXX.
  if digits like '232%' then digits := substr(digits, 4); elsif digits like '0%' then digits := substr(digits, 2); end if;
  if length(digits) <> 8 then raise exception 'Enter a Sierra Leone mobile number, e.g. 076 123 456.'; end if;
  if length(trim(coalesce(p_name, ''))) < 3 then raise exception 'Enter the name on the Mobile Money account.'; end if;

  perform public.my_referral_code(); -- makes sure the row exists
  update public.referral_codes
     set payout_provider = p_provider,
         payout_number = '+232' || digits,
         payout_name = trim(p_name),
         payout_updated_at = now()
   where user_id = uid;
end $$;

notify pgrst, 'reload schema';
