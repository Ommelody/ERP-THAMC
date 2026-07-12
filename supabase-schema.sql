-- ============================================================
-- ระบบ ERP ศูนย์การแพทย์ธรรมศาสตร์ — Supabase schema
-- โปรเจกต์: hkqyeeonfyzlbnimztuz
-- วิธีใช้: เปิด Supabase → SQL Editor → New query → วางทั้งหมด → Run
-- (สร้างตาราง + เปิด RLS แบบอนุญาต anon อ่าน/เขียน สำหรับช่วงนำร่อง)
-- ============================================================

-- ---------- ตารางคำขออนุมัติงบประมาณ (BR) ----------
create table if not exists public.budget_requests (
  id            text primary key,
  at            text,
  requester     text,
  email         text,
  dept          text,
  dn            text,
  tel           text,
  pos           text,
  item_name     text,
  reason        text,
  qty           numeric default 0,
  unit          text,
  value         numeric default 0,
  needed_date   text,
  cat           text,
  proc_type     text default 'ซื้อ',
  med           boolean default false,
  has_code      boolean default false,
  code          text default '',
  status        text default 'รออนุมัติผู้บริหาร',
  budget_type   text,
  budget_name   text,
  budget_code   text default '',
  pr_id         text default '',
  log           jsonb default '[]'::jsonb,
  created_at    timestamptz default now()
);

-- ---------- ตารางใบขอซื้อ (PR) ----------
create table if not exists public.purchase_requests (
  id            text primary key,
  br_id         text,
  requester     text,
  dept          text,
  dn            text,
  tel           text,
  pos           text,
  items         jsonb default '[]'::jsonb,
  sub           numeric default 0,
  vat           numeric default 0,
  total         numeric default 0,
  cat           text,
  exp           text,
  proc_type     text,
  urgency       text default 'ปกติ',
  reason        text,
  committee     jsonb default '[]'::jsonb,
  condition     text default '',
  po            text default '',
  vendor        text default '',
  docs          jsonb default '[]'::jsonb,
  status        text default 'ยื่นเสนอซื้อ',
  at            text,
  needed_date   text,
  budget_code   text default '',
  log           jsonb default '[]'::jsonb,
  created_at    timestamptz default now()
);

-- ---------- (ตัวเลือก) ทะเบียนออกรหัสพัสดุจาก Item Master Pro ----------
-- สำหรับฐานข้อมูลที่สร้างไว้ก่อนหน้า: เพิ่มคอลัมน์เลขที่งบประมาณ (Budget Reserve No)
alter table public.budget_requests   add column if not exists budget_code text default '';
alter table public.purchase_requests add column if not exists budget_code text default '';
create table if not exists public.item_code_requests (
  id          bigint generated always as identity primary key,
  br_id       text,
  item_name   text,
  qty         numeric default 0,
  unit        text,
  dept        text,
  dept_name   text,
  budget_code text default '',
  budget_plan text default '',
  value       numeric default 0,
  requested_by text,
  requested_at text,
  code        text,
  status      text default 'requested',   -- requested | issued
  created_at  timestamptz default now()
);
-- สำหรับฐานข้อมูลเดิม: เพิ่มคอลัมน์รายละเอียดคำขอออกรหัส
alter table public.item_code_requests add column if not exists qty numeric default 0;
alter table public.item_code_requests add column if not exists unit text;
alter table public.item_code_requests add column if not exists dept text;
alter table public.item_code_requests add column if not exists dept_name text;
alter table public.item_code_requests add column if not exists budget_code text default '';
alter table public.item_code_requests add column if not exists budget_plan text default '';
alter table public.item_code_requests add column if not exists value numeric default 0;
alter table public.item_code_requests add column if not exists requested_at text;

-- ---------- ตารางข้อมูล SAP (อัปโหลดจาก ERP แบบ upsert กันซ้ำ ต่อยอดไปข้างหน้า) ----------
create table if not exists public.sap_po (
  doc text primary key, pf text, post text, deliv text, vn text, vc text,
  dept text, dn text, who text, val numeric default 0, qty numeric default 0,
  open numeric default 0, ln int default 0, tr text, gd int default 0, ap int default 0,
  paid numeric default 0, od int default 0, od_days int default 0, exp text, grl jsonb default '[]',
  updated_at timestamptz default now()
);
create table if not exists public.sap_ap (
  doc text primary key, post text, vn text, vc text, dept text, dn text,
  val numeric default 0, paid boolean default false, pay_date text, pay_doc text,
  method text, base text, exp text, updated_at timestamptz default now()
);
create table if not exists public.sap_payment (
  doc text primary key, series text, post text, due text, vn text, vc text,
  total numeric default 0, method text, inv_count int default 0, purpose text,
  updated_at timestamptz default now()
);
create table if not exists public.sap_budget (
  exp text primary key, name text, plan text, sub text,
  current numeric default 0, commit numeric default 0, actual numeric default 0,
  avail numeric default 0, dept text, dept_code text, updated_at timestamptz default now()
);
alter table public.sap_po      enable row level security;
alter table public.sap_ap      enable row level security;
alter table public.sap_payment enable row level security;
alter table public.sap_budget  enable row level security;
drop policy if exists "anon all sap_po" on public.sap_po;
create policy "anon all sap_po" on public.sap_po for all to anon using (true) with check (true);
drop policy if exists "anon all sap_ap" on public.sap_ap;
create policy "anon all sap_ap" on public.sap_ap for all to anon using (true) with check (true);
drop policy if exists "anon all sap_pay" on public.sap_payment;
create policy "anon all sap_pay" on public.sap_payment for all to anon using (true) with check (true);
drop policy if exists "anon all sap_bud" on public.sap_budget;
create policy "anon all sap_bud" on public.sap_budget for all to anon using (true) with check (true);

-- ---------- ฐานข้อมูลกลางรหัสพัสดุ (Item Master Pro V2 เขียนลง — ERP อ่านมาค้นหา) ----------
-- โปรแกรม Item Master Pro V2 sync รายการรหัสพัสดุทั้งหมดมาที่ตารางนี้
-- (ผ่าน Export/DTW หรือ API) ระบบ ERP จะ query แบบ live เพื่อค้นหารหัสตอนจัดสรรงบ
create table if not exists public.item_master (
  code       text primary key,      -- รหัสพัสดุ เช่น 8010130012
  name       text,                  -- ชื่อรายการ
  category   text,                  -- หมวด/กลุ่มพัสดุ
  unit       text,                  -- หน่วยนับ
  active     boolean default true,
  updated_at timestamptz default now()
);
create index if not exists item_master_name_idx on public.item_master using gin (to_tsvector('simple', coalesce(name,'')));

-- ตัวอย่างรหัสตั้งต้น (Item Pro V2 จะ sync ทับด้วยข้อมูลจริง)
insert into public.item_master (code,name,category,unit) values
  ('8010130012','เก้าอี้กลมหมุนปรับสูง-ต่ำได้ CH01','ครุภัณฑ์สำนักงาน - เก้าอี้','ตัว'),
  ('8010830022','TP-04B โซฟาเป้าไข่','ครุภัณฑ์สำนักงาน','ตัว'),
  ('8010840001','ถังดับเพลิง Cylinder Assembly','ครุภัณฑ์สำนักงาน - ถังดับเพลิง','ถัง'),
  ('8010850006','ม่านมากับอาคาร','ครุภัณฑ์สำนักงาน - ผ้าม่าน','ชุด'),
  ('8010670001','ป้ายอาคารกว้างหรือยาวเกิน 1.20 เมตร','ครุภัณฑ์สำนักงาน - ป้าย','ป้าย'),
  ('8010470002','ตู้วางน้ำดื่มขนาด 1.50*1.10','ครุภัณฑ์สำนักงาน - เคาน์เตอร์','ตู้'),
  ('8010470003','ชุดเคาน์เตอร์ลอย','ครุภัณฑ์สำนักงาน - เคาน์เตอร์','ชุด'),
  ('8010540001','เครื่องนับเหรียญ','ครุภัณฑ์สำนักงาน - เครื่องนับเหรียญ','เครื่อง'),
  ('8010550001','เครื่องนับธนบัตร','ครุภัณฑ์สำนักงาน - เครื่องนับธนบัตร','เครื่อง'),
  ('8100305021','ชุดเครื่องมือผ่าตัดใหญ่','ครุภัณฑ์การแพทย์','ชุด'),
  ('8100208033','ตู้แช่เวชภัณฑ์ควบคุมอุณหภูมิ','ครุภัณฑ์การแพทย์','ตู้'),
  ('8100402011','เครื่องปั่นเหวี่ยงตกตะกอน','ครุภัณฑ์การแพทย์','เครื่อง'),
  ('8100207120','รถเข็นทำแผลสแตนเลส','ครุภัณฑ์การแพทย์','คัน'),
  ('8100110045','เตียงผู้ป่วยไฟฟ้า 3 ไก','ครุภัณฑ์การแพทย์','เตียง'),
  ('8100305088','เครื่องวัดความดันโลหิตอัตโนมัติ','ครุภัณฑ์การแพทย์','เครื่อง')
on conflict (code) do nothing;


-- ============================================================
-- RLS: เปิดใช้งาน แล้วอนุญาตให้ anon (public) อ่าน/เขียนได้
-- (เหมาะกับช่วงทดลอง/นำร่อง — ภายหลังควรผูกกับ auth.uid())
-- ============================================================
alter table public.budget_requests    enable row level security;
alter table public.purchase_requests  enable row level security;
alter table public.item_code_requests enable row level security;
alter table public.item_master        enable row level security;

drop policy if exists "anon all br" on public.budget_requests;
create policy "anon all br" on public.budget_requests
  for all to anon using (true) with check (true);

drop policy if exists "anon all pr" on public.purchase_requests;
create policy "anon all pr" on public.purchase_requests
  for all to anon using (true) with check (true);

drop policy if exists "anon all icr" on public.item_code_requests;
create policy "anon all icr" on public.item_code_requests
  for all to anon using (true) with check (true);

drop policy if exists "anon read im" on public.item_master;
create policy "anon read im" on public.item_master
  for all to anon using (true) with check (true);

-- ============================================================
-- (ตัวเลือก) เปิด Realtime เพื่อให้หลายผู้ใช้เห็นการอัปเดตทันที
-- ============================================================
alter publication supabase_realtime add table public.budget_requests;
alter publication supabase_realtime add table public.purchase_requests;
alter publication supabase_realtime add table public.item_code_requests;
alter publication supabase_realtime add table public.item_master;
alter publication supabase_realtime add table public.sap_po;
alter publication supabase_realtime add table public.sap_ap;
alter publication supabase_realtime add table public.sap_payment;
alter publication supabase_realtime add table public.sap_budget;
