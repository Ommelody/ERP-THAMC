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
  log           jsonb default '[]'::jsonb,
  created_at    timestamptz default now()
);

-- ---------- (ตัวเลือก) ทะเบียนออกรหัสพัสดุจาก Item Master Pro ----------
create table if not exists public.item_code_requests (
  id          bigint generated always as identity primary key,
  br_id       text,
  item_name   text,
  requested_by text,
  code        text,
  status      text default 'requested',   -- requested | issued
  created_at  timestamptz default now()
);

-- ============================================================
-- RLS: เปิดใช้งาน แล้วอนุญาตให้ anon (public) อ่าน/เขียนได้
-- (เหมาะกับช่วงทดลอง/นำร่อง — ภายหลังควรผูกกับ auth.uid())
-- ============================================================
alter table public.budget_requests    enable row level security;
alter table public.purchase_requests  enable row level security;
alter table public.item_code_requests enable row level security;

drop policy if exists "anon all br" on public.budget_requests;
create policy "anon all br" on public.budget_requests
  for all to anon using (true) with check (true);

drop policy if exists "anon all pr" on public.purchase_requests;
create policy "anon all pr" on public.purchase_requests
  for all to anon using (true) with check (true);

drop policy if exists "anon all icr" on public.item_code_requests;
create policy "anon all icr" on public.item_code_requests
  for all to anon using (true) with check (true);

-- ============================================================
-- (ตัวเลือก) เปิด Realtime เพื่อให้หลายผู้ใช้เห็นการอัปเดตทันที
-- ============================================================
alter publication supabase_realtime add table public.budget_requests;
alter publication supabase_realtime add table public.purchase_requests;
