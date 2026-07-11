-- (ตัวเลือก) ทะเบียนออกรหัสพัสดุ — ใช้เป็น API รับส่งกับโปรแกรม Item Master Pro
create table if not exists public.item_code_requests (
  id          bigint generated always as identity primary key,
  br_id       text,
  item_name   text,
  requested_by text,
  code        text default '',
  status      text default 'requested',   -- requested | issued
  created_at  timestamptz default now()
);
alter table public.item_code_requests enable row level security;
drop policy if exists "anon all icr" on public.item_code_requests;
create policy "anon all icr" on public.item_code_requests
  for all to anon using (true) with check (true);
