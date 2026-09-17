-- ============================================================
-- GESTORES SYSTEM — schema.sql
-- Ejecuta este archivo PRIMERO en el SQL Editor de Supabase.
-- Crea todas las tablas del sistema de gestores y líderes.
-- ============================================================

-- ---------- EXTENSIONES ----------
create extension if not exists "pgcrypto";

-- ============================================================
-- PERFILES (extiende auth.users, que ya gestiona Supabase Auth)
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default '',
  role text not null check (role in ('admin', 'leader', 'gestor')),
  status text not null default 'active' check (status in ('active', 'inactive', 'pending_approval')),
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil de aplicación de cada usuario autenticado (admin, líder o gestor).';

-- ============================================================
-- LÍDERES
-- ============================================================
create table public.leaders (
  id uuid primary key references public.profiles(id) on delete cascade,
  override_percentage numeric(5,2) not null default 0 check (override_percentage >= 0 and override_percentage <= 100),
  created_at timestamptz not null default now()
);

-- ============================================================
-- GESTORES
-- ============================================================
create table public.gestores (
  id uuid primary key references public.profiles(id) on delete cascade,
  leader_id uuid references public.leaders(id) on delete set null,
  is_vip boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_gestores_leader_id on public.gestores (leader_id);

-- ============================================================
-- CATÁLOGO DE GESTORES (independiente del catálogo de la tienda)
-- ============================================================
create table public.catalogo_gestor (
  id bigint generated always as identity primary key,
  name text not null,
  description text default '',
  price numeric(10,2) not null check (price >= 0),
  commission_type text not null check (commission_type in ('percent', 'fixed')),
  commission_value numeric(10,2) not null check (commission_value >= 0),
  stock int,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- VALES
-- ============================================================
create sequence public.vale_number_seq start 1;

create table public.vales (
  id bigint generated always as identity primary key,
  vale_number text unique not null default ('V-' || lpad(nextval('public.vale_number_seq')::text, 6, '0')),
  gestor_id uuid not null references public.gestores(id) on delete cascade,
  customer_name text not null,
  customer_phone text not null,
  customer_address text,
  delivery_method text not null check (delivery_method in ('pickup', 'delivery')),
  notes text,
  total_amount numeric(10,2) not null default 0,
  status text not null default 'draft' check (status in ('draft', 'sent', 'approved', 'rejected', 'completed')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  completed_at timestamptz,
  rejection_reason text
);

create index idx_vales_gestor_id on public.vales (gestor_id);
create index idx_vales_status on public.vales (status);

-- ============================================================
-- ÍTEMS DEL VALE
-- ============================================================
create table public.vale_items (
  id bigint generated always as identity primary key,
  vale_id bigint not null references public.vales(id) on delete cascade,
  product_id bigint references public.catalogo_gestor(id),
  product_name text not null, -- copia del nombre al momento de la venta (por si el producto cambia luego)
  quantity int not null check (quantity > 0),
  unit_price numeric(10,2) not null check (unit_price >= 0),
  commission_amount numeric(10,2) not null default 0
);

create index idx_vale_items_vale_id on public.vale_items (vale_id);

-- ============================================================
-- COMISIONES (se generan automáticamente al aprobar un vale)
-- ============================================================
create table public.commissions (
  id bigint generated always as identity primary key,
  vale_id bigint not null references public.vales(id) on delete cascade,
  gestor_id uuid not null references public.gestores(id),
  leader_id uuid references public.leaders(id),
  gestor_commission numeric(10,2) not null default 0,
  leader_commission numeric(10,2) not null default 0,
  status text not null default 'pending' check (status in ('pending', 'paid')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create unique index idx_commissions_vale_unique on public.commissions (vale_id);
create index idx_commissions_gestor_id on public.commissions (gestor_id);
create index idx_commissions_leader_id on public.commissions (leader_id);
create index idx_commissions_status on public.commissions (status);

-- ============================================================
-- PAGOS (historial de pagos en efectivo)
-- ============================================================
create table public.payouts (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles(id),
  amount numeric(10,2) not null check (amount >= 0),
  payment_date timestamptz not null default now(),
  notes text
);

create index idx_payouts_profile_id on public.payouts (profile_id);

-- ============================================================
-- CONFIGURACIÓN GENERAL (ej. número de WhatsApp de administración)
-- ============================================================
create table public.settings (
  key text primary key,
  value text not null
);

insert into public.settings (key, value) values
  ('whatsapp_admin_number', 'TU_NUMERO_AQUI'),
  ('default_leader_override_percentage', '10');
