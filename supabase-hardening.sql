-- ============================================================
-- ระบบ ERP ศูนย์การแพทย์ธรรมศาสตร์ — สคริปต์เตรียมขึ้นระบบจริง (Hardening)
-- โปรเจกต์: hkqyeeonfyzlbnimztuz
--
-- ⚠ รันหลังจาก supabase-schema.sql + supabase-seed-sap.sql เรียบร้อยแล้ว
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งหมด → Run
--
-- สคริปต์นี้แก้ 4 เรื่องหลักก่อนขึ้นใช้งานจริง:
--   (1) ผูกสิทธิ์กับ Supabase Auth จริง (เลิกให้ anon เขียนได้ทุกอย่าง)
--   (2) เลิกเก็บรหัสผ่าน plaintext — ย้ายไป auth.users + ตาราง profiles
--   (3) ออกเลขที่เอกสาร (BR/PR) แบบ atomic กันเลขซ้ำเมื่อใช้พร้อมกัน
--   (4) ตัดงบ/จัดสรรงบแบบ transaction กัน race condition งบติดลบ
-- ============================================================


-- ============================================================
-- ส่วนที่ 1 — ตาราง profiles: เก็บบทบาท (role) ผูกกับผู้ใช้ Auth
-- ============================================================
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  name       text,
  role       text default 'requester',   -- admin | requester | budget | procurement | finance | exec
  dept       text,                        -- รหัสหน่วยงาน เช่น 13ORD
  dept_name  text,                        -- ชื่อหน่วยงาน เช่น ห้องผ่าตัด
  pos        text,                        -- ตำแหน่ง
  tel        text,                        -- เบอร์ติดต่อ
  active     boolean default true,
  created_at timestamptz default now()
);
-- เผื่อรันซ้ำบนฐานที่มีตาราง profiles เดิมอยู่แล้ว — เติมคอลัมน์ให้ครบ
 alter table public.profiles add column if not exists dept      text;
alter table public.profiles add column if not exists dept_name text;
alter table public.profiles add column if not exists pos       text;
alter table public.profiles add column if not exists tel       text;

alter table public.profiles enable row level security;

-- ---------- helper: เช็ค role ของผู้ใช้ปัจจุบัน ----------
-- ⚠ ต้องสร้างฟังก์ชันก่อน policy ที่เรียกใช้ มิฉะนั้นจะ error "function does not exist"
-- SECURITY DEFINER = อ่านตาราง profiles ได้โดยไม่ติด RLS ของ profiles เอง
create or replace function public.is_role(roles text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and active = true
      and role = any(roles)
  );
$$;

create or replace function public.my_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active = true;
$$;

-- ทุกคนที่ล็อกอินแล้วอ่าน profile ของตัวเองได้ / admin อ่านได้ทุกคน
drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read" on public.profiles
  for select to authenticated
  using ( id = auth.uid() or public.is_role(array['admin']) );

-- แก้ไข profile ได้เฉพาะ admin (กันผู้ใช้เลื่อนสิทธิ์ตัวเอง)
drop policy if exists "profiles admin write" on public.profiles;
create policy "profiles admin write" on public.profiles
  for all to authenticated
  using ( public.is_role(array['admin']) )
  with check ( public.is_role(array['admin']) );

-- ---------- สร้าง profile อัตโนมัติเมื่อมีผู้ใช้ Auth ใหม่ ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role, dept, dept_name, pos, tel)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'requester'),
    new.raw_user_meta_data->>'dept',
    new.raw_user_meta_data->>'dept_name',
    new.raw_user_meta_data->>'pos',
    new.raw_user_meta_data->>'tel'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- ส่วนที่ 2 — RLS ใหม่: เปลี่ยนจาก anon(true) → authenticated + role
-- ============================================================
-- เพิ่มคอลัมน์เจ้าของ (อีเมลผู้สร้าง) เพื่อให้ผู้ขอซื้ออ่าน/แก้เฉพาะของตัวเองได้
alter table public.budget_requests   add column if not exists owner_email text;
alter table public.purchase_requests add column if not exists owner_email text;

-- ---------- ลบ policy anon แบบเปิดกว้างทั้งหมด ----------
drop policy if exists "anon all br"  on public.budget_requests;
drop policy if exists "anon all pr"  on public.purchase_requests;
drop policy if exists "anon all icr" on public.item_code_requests;
drop policy if exists "anon read im" on public.item_master;
drop policy if exists "anon all sap_po"  on public.sap_po;
drop policy if exists "anon all sap_ap"  on public.sap_ap;
drop policy if exists "anon all sap_pay" on public.sap_payment;
drop policy if exists "anon all sap_bud" on public.sap_budget;
-- ตาราง app_users เดิม (plaintext) — เลิกใช้แล้ว ปิดสิทธิ์ anon
drop policy if exists "anon all users" on public.app_users;

-- ---------- budget_requests (BR) ----------
-- อ่าน: เจ้าของคำขอ หรือ role ที่เกี่ยวกับกระบวนการ
drop policy if exists "br read" on public.budget_requests;
create policy "br read" on public.budget_requests
  for select to authenticated
  using (
    owner_email = auth.jwt()->>'email'
    or public.is_role(array['admin','budget','exec','procurement','finance'])
  );

-- สร้าง: ผู้ล็อกอินสร้างคำขอในนามตัวเองเท่านั้น
drop policy if exists "br insert" on public.budget_requests;
create policy "br insert" on public.budget_requests
  for insert to authenticated
  with check (
    owner_email = auth.jwt()->>'email'
    or public.is_role(array['admin','requester'])
  );

-- แก้ไข: เจ้าของ (ตอนถูกส่งกลับแก้ไข) หรือ role อนุมัติ/จัดสรร
drop policy if exists "br update" on public.budget_requests;
create policy "br update" on public.budget_requests
  for update to authenticated
  using (
    owner_email = auth.jwt()->>'email'
    or public.is_role(array['admin','budget','exec'])
  );

drop policy if exists "br delete" on public.budget_requests;
create policy "br delete" on public.budget_requests
  for delete to authenticated using ( public.is_role(array['admin']) );

-- ---------- purchase_requests (PR) ----------
drop policy if exists "pr read" on public.purchase_requests;
create policy "pr read" on public.purchase_requests
  for select to authenticated
  using (
    owner_email = auth.jwt()->>'email'
    or public.is_role(array['admin','budget','exec','procurement','finance'])
  );

drop policy if exists "pr insert" on public.purchase_requests;
create policy "pr insert" on public.purchase_requests
  for insert to authenticated
  with check ( public.is_role(array['admin','requester']) );

drop policy if exists "pr update" on public.purchase_requests;
create policy "pr update" on public.purchase_requests
  for update to authenticated
  using (
    owner_email = auth.jwt()->>'email'
    or public.is_role(array['admin','procurement','budget','finance'])
  );

drop policy if exists "pr delete" on public.purchase_requests;
create policy "pr delete" on public.purchase_requests
  for delete to authenticated using ( public.is_role(array['admin']) );

-- ---------- item_code_requests (คิวออกรหัส Item Pro) ----------
drop policy if exists "icr read" on public.item_code_requests;
create policy "icr read" on public.item_code_requests
  for select to authenticated
  using ( public.is_role(array['admin','budget','procurement']) );

drop policy if exists "icr write" on public.item_code_requests;
create policy "icr write" on public.item_code_requests
  for all to authenticated
  using ( public.is_role(array['admin','budget']) )
  with check ( public.is_role(array['admin','budget']) );

-- ---------- item_master (ค้นหารหัสพัสดุ — อ่านอย่างเดียวจากฝั่งแอป) ----------
drop policy if exists "im read" on public.item_master;
create policy "im read" on public.item_master
  for select to authenticated using ( true );
-- เขียน item_master เฉพาะ admin (ปกติ Item Pro V2 เขียนผ่าน service_role)
drop policy if exists "im write" on public.item_master;
create policy "im write" on public.item_master
  for all to authenticated
  using ( public.is_role(array['admin']) )
  with check ( public.is_role(array['admin']) );

-- ---------- ตาราง SAP (อ่านได้ทุก role ที่ล็อกอิน / เขียนเฉพาะนำเข้าข้อมูล) ----------
-- อ่าน
drop policy if exists "sap_po read"  on public.sap_po;
drop policy if exists "sap_ap read"  on public.sap_ap;
drop policy if exists "sap_pay read" on public.sap_payment;
drop policy if exists "sap_bud read" on public.sap_budget;
create policy "sap_po read"  on public.sap_po       for select to authenticated using ( true );
create policy "sap_ap read"  on public.sap_ap       for select to authenticated using ( true );
create policy "sap_pay read" on public.sap_payment  for select to authenticated using ( true );
create policy "sap_bud read" on public.sap_budget   for select to authenticated using ( true );

-- เขียน (นำเข้า SAP): เฉพาะ procurement / budget / finance / admin
drop policy if exists "sap_po write"  on public.sap_po;
drop policy if exists "sap_ap write"  on public.sap_ap;
drop policy if exists "sap_pay write" on public.sap_payment;
drop policy if exists "sap_bud write" on public.sap_budget;
create policy "sap_po write"  on public.sap_po      for all to authenticated
  using ( public.is_role(array['admin','procurement','budget','finance']) )
  with check ( public.is_role(array['admin','procurement','budget','finance']) );
create policy "sap_ap write"  on public.sap_ap      for all to authenticated
  using ( public.is_role(array['admin','procurement','budget','finance']) )
  with check ( public.is_role(array['admin','procurement','budget','finance']) );
create policy "sap_pay write" on public.sap_payment for all to authenticated
  using ( public.is_role(array['admin','procurement','budget','finance']) )
  with check ( public.is_role(array['admin','procurement','budget','finance']) );
create policy "sap_bud write" on public.sap_budget  for all to authenticated
  using ( public.is_role(array['admin','procurement','budget','finance']) )
  with check ( public.is_role(array['admin','procurement','budget','finance']) );


-- ============================================================
-- ส่วนที่ 2.5 — ตารางตั้งค่าระบบ (เก็บ config ที่เดิมอยู่ใน localStorage)
-- ============================================================
-- เก็บรายการประเภทพัสดุ (exps) และค่าตั้งอื่น ๆ เป็น key/value
create table if not exists public.app_config (
  k text primary key,
  v jsonb not null default '[]'::jsonb,
  updated_at timestamptz default now()
);
alter table public.app_config enable row level security;
drop policy if exists "cfg read" on public.app_config;
create policy "cfg read" on public.app_config
  for select to authenticated using ( true );
drop policy if exists "cfg write" on public.app_config;
create policy "cfg write" on public.app_config
  for all to authenticated
  using ( public.is_role(array['admin','budget','procurement']) )
  with check ( public.is_role(array['admin','budget','procurement']) );


-- ============================================================
-- ส่วนที่ 3 — ออกเลขที่เอกสารแบบ atomic (กันเลขซ้ำเมื่อใช้พร้อมกัน)
-- ============================================================
-- ใช้ตารางตัวนับต่อเดือน กันเลขชนแม้หลายคนกดสร้างพร้อมกัน
create table if not exists public.doc_counters (
  kind  text not null,          -- 'BR' | 'PR'
  ym    text not null,          -- รหัสปี-เดือน เช่น 6807 (ก.ค. 2568)
  n     int  not null default 0,
  primary key (kind, ym)
);
alter table public.doc_counters enable row level security;
drop policy if exists "counters none" on public.doc_counters;
-- ไม่เปิดสิทธิ์ตรงให้ client — เข้าถึงผ่าน RPC (security definer) เท่านั้น

create or replace function public.next_doc_id(p_kind text, p_ym text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare v_n int;
begin
  insert into public.doc_counters (kind, ym, n)
  values (p_kind, p_ym, 1)
  on conflict (kind, ym) do update set n = public.doc_counters.n + 1
  returning n into v_n;
  return p_kind || '-' || p_ym || '-' || lpad(v_n::text, 4, '0');
end;
$$;

grant execute on function public.next_doc_id(text, text) to authenticated;

-- ---------- ออกรหัสพัสดุแบบไม่ชน (ใช้ตอน budget ออกรหัสเองเมื่อ Item Pro ยังไม่ตอบ) ----------
create sequence if not exists public.item_code_seq start 100001;
create or replace function public.next_item_code()
returns text
language plpgsql security definer
set search_path = public
as $$
declare v_code text;
begin
  loop
    v_code := '81' || lpad(nextval('public.item_code_seq')::text, 8, '0');
    exit when not exists (select 1 from public.item_master where code = v_code);
  end loop;
  return v_code;
end;
$$;
grant execute on function public.next_item_code() to authenticated;


-- ============================================================
-- ส่วนที่ 4 — จัดสรรงบแบบ transaction (กัน race condition งบติดลบ)
-- ============================================================
-- ตัดยอด Available ของเลขงบ + อัปเดตสถานะ BR ในทรานแซกชันเดียว
-- คืน jsonb {ok, avail, msg} — ฝั่งแอปเช็ค .ok ก่อนแสดงผล
create or replace function public.allocate_budget(
  p_br_id text,
  p_code  text,
  p_fy    int,
  p_value numeric,
  p_item_code text default null
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare v_avail numeric; v_role text;
begin
  -- ตรวจสิทธิ์: เฉพาะ budget / admin เท่านั้นที่จัดสรรงบได้
  v_role := public.my_role();
  if v_role is null or v_role not in ('budget','admin') then
    return jsonb_build_object('ok', false, 'msg', 'ไม่มีสิทธิ์จัดสรรงบ');
  end if;

  -- ล็อกแถวงบไว้ก่อน กันสองคนตัดพร้อมกัน
  select avail into v_avail from public.sap_budget where exp = p_code and fy = p_fy for update;
  if v_avail is null then
    return jsonb_build_object('ok', false, 'msg', 'ไม่พบเลขที่งบประมาณ ' || p_code || ' (ปีงบ ' || p_fy || ')');
  end if;
  if v_avail < p_value then
    return jsonb_build_object('ok', false, 'avail', v_avail,
      'msg', 'งบคงเหลือไม่พอ (คงเหลือ ' || v_avail || ' ต้องการ ' || p_value || ')');
  end if;

  -- ตัดยอด + อัปเดต BR
  update public.sap_budget
    set avail = avail - p_value, commit = commit + p_value, updated_at = now()
    where exp = p_code and fy = p_fy;

  update public.budget_requests
    set status = 'จัดสรรงบแล้ว',
        budget_code = p_code,
        code = coalesce(p_item_code, code),
        has_code = (p_item_code is not null),
        log = coalesce(log, '[]'::jsonb) ||
              jsonb_build_object('s','จัดสรรงบ','by',coalesce((auth.jwt()->>'email'),'ระบบ'),'at',now())
    where id = p_br_id;

  return jsonb_build_object('ok', true, 'avail', v_avail - p_value);
end;
$$;
grant execute on function public.allocate_budget(text, text, int, numeric, text) to authenticated;


-- ============================================================
-- ส่วนที่ 4.5 — แยกข้อมูลตามปีงบประมาณราชการ (FY, เริ่ม 1 ต.ค.)
-- ============================================================
-- คำขอ BR/PR: เพิ่มคอลัมน์ปีงบ (พ.ศ.)
alter table public.budget_requests   add column if not exists fy int;
alter table public.purchase_requests add column if not exists fy int;

-- ตารางงบ SAP: เพิ่มปีงบ แล้วเปลี่ยน primary key เป็น (exp, fy)
-- เพื่อให้เก็บงบหลายปีพร้อมกันได้ (เลขงบเดียวกันปรากฏได้ทุกปี)
alter table public.sap_budget add column if not exists fy int;
-- สมมุติข้อมูลเดิมที่ยังไม่มีปีงบ = ปีงบ 2569 (แก้ตัวเลขนี้ถ้าข้อมูลเดิมเป็นปีอื่น)
update public.sap_budget set fy = 2569 where fy is null;
alter table public.sap_budget alter column fy set not null;
alter table public.sap_budget drop constraint if exists sap_budget_pkey;
alter table public.sap_budget add constraint sap_budget_pkey primary key (exp, fy);

-- ดัชนีช่วยกรองตามปีงบ
create index if not exists idx_br_fy on public.budget_requests(fy);
create index if not exists idx_pr_fy on public.purchase_requests(fy);


-- ============================================================
-- ส่วนที่ 5 — เลิกใช้ตารางรหัสผ่าน plaintext เดิม
-- ============================================================
-- app_users เก็บรหัสผ่านแบบอ่านได้ — เมื่อย้ายไป Supabase Auth แล้วให้ลบทิ้ง
-- (คอมเมนต์ไว้ก่อน กันลบพลาด — เอาคอมเมนต์ออกเมื่อพร้อมย้ายผู้ใช้ครบแล้ว)
-- drop table if exists public.app_users;


-- ============================================================
-- ส่วนที่ 6 — สร้างผู้ดูแลระบบคนแรก (ทำครั้งเดียวหลังรันสคริปต์นี้)
-- ============================================================
-- 1) Supabase Dashboard → Authentication → Users → Add user
--    (ใส่ email + password จริงของผู้ดูแล — ระบบจะสร้าง profile ให้อัตโนมัติ role=requester)
-- 2) กลับมาที่ SQL Editor รันบรรทัดล่าง แก้อีเมลให้ตรงกับผู้ดูแลจริง:
--
-- update public.profiles set role='admin', name='ผู้ดูแลระบบ'
--   where email = 'admin@example.com';
--
-- ตัวอย่างกำหนดข้อมูลผู้ขอซื้อ (หน่วยงาน/ตำแหน่ง/เบอร์ติดต่อ) ให้ผู้ใช้แต่ละคน:
-- update public.profiles
--   set role='requester', name='กมลวรรณ ศรีสุข',
--       dept='13ORD', dept_name='ห้องผ่าตัด', pos='พยาบาลวิชาชีพ', tel='02-xxx-xxxx'
--   where email = 'user@example.com';
--
-- จากนั้นผู้ดูแลล็อกอินแล้วเพิ่มผู้ใช้/กำหนด role คนอื่นผ่านหน้า "จัดการผู้ใช้" ได้
-- ============================================================
