-- ตารางผู้ใช้ระบบ (สำหรับหน้า "จัดการผู้ใช้ + สิทธิ์" ของแอดมิน)
-- รันใน Supabase SQL Editor เพื่อเปิดใช้งานการล็อกอิน/จัดการสิทธิ์แบบถาวร
create table if not exists public.app_users (
  username    text primary key,
  password    text not null,
  name        text,
  role        text default 'requester',   -- admin | requester | budget | procurement | finance | exec
  active      boolean default true,
  created_at  timestamptz default now()
);
alter table public.app_users enable row level security;
drop policy if exists "anon all users" on public.app_users;
create policy "anon all users" on public.app_users
  for all to anon using (true) with check (true);

-- บัญชีผู้ดูแลระบบเริ่มต้น (เปลี่ยนรหัสผ่านหลังใช้งานจริง)
insert into public.app_users (username,password,name,role,active) values
  ('Admin','Admin','ผู้ดูแลระบบ','admin',true)
on conflict (username) do nothing;
