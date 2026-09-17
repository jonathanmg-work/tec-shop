-- ============================================================
-- GESTORES SYSTEM — policies.sql
-- Ejecuta este archivo TERCERO (después de helpers.sql).
-- Aquí vive la seguridad real del sistema: cada tabla queda
-- bloqueada por defecto y solo se abre exactamente lo que cada
-- rol necesita. Esto se aplica en el servidor de Supabase, así
-- que no depende de que el frontend "se porte bien".
-- ============================================================

-- ---------- Activar RLS en todas las tablas ----------
alter table public.profiles enable row level security;
alter table public.leaders enable row level security;
alter table public.gestores enable row level security;
alter table public.catalogo_gestor enable row level security;
alter table public.vales enable row level security;
alter table public.vale_items enable row level security;
alter table public.commissions enable row level security;
alter table public.payouts enable row level security;
alter table public.settings enable row level security;

-- ============================================================
-- PROFILES
-- ============================================================
create policy profiles_select_own
  on public.profiles for select
  using (id = auth.uid());

create policy profiles_select_admin
  on public.profiles for select
  using (public.is_admin());

create policy profiles_select_leader_de_su_gestor
  on public.profiles for select
  using (
    exists (select 1 from public.gestores g where g.id = profiles.id and g.leader_id = auth.uid())
  );

create policy profiles_update_admin
  on public.profiles for update
  using (public.is_admin());

-- Nota: la creación de perfiles (nuevos usuarios) se hace únicamente
-- a través de la Edge Function "create-user", que usa la service_role
-- key y por lo tanto no necesita (ni debe tener) política de INSERT aquí.

-- ============================================================
-- LEADERS
-- ============================================================
create policy leaders_select_own_or_admin
  on public.leaders for select
  using (id = auth.uid() or public.is_admin());

create policy leaders_update_admin
  on public.leaders for update
  using (public.is_admin());

-- ============================================================
-- GESTORES
-- ============================================================
create policy gestores_select_own
  on public.gestores for select
  using (id = auth.uid());

create policy gestores_select_admin
  on public.gestores for select
  using (public.is_admin());

create policy gestores_select_su_lider
  on public.gestores for select
  using (leader_id = auth.uid());

create policy gestores_update_admin
  on public.gestores for update
  using (public.is_admin());

-- ============================================================
-- CATÁLOGO DE GESTORES
-- ============================================================
create policy catalogo_select_autenticados
  on public.catalogo_gestor for select
  using (auth.role() = 'authenticated');

create policy catalogo_insert_admin
  on public.catalogo_gestor for insert
  with check (public.is_admin());

create policy catalogo_update_admin
  on public.catalogo_gestor for update
  using (public.is_admin());

create policy catalogo_delete_admin
  on public.catalogo_gestor for delete
  using (public.is_admin());

-- ============================================================
-- VALES
-- Los líderes NO tienen política aquí a propósito: no deben ver
-- nombre/teléfono/dirección del cliente. Consultan sus vales
-- agregados a través de la función get_lider_vales() (ver rpc.sql),
-- que expone solo columnas seguras.
-- ============================================================
create policy vales_select_propio_gestor
  on public.vales for select
  using (gestor_id = auth.uid());

create policy vales_select_admin
  on public.vales for select
  using (public.is_admin());

create policy vales_insert_propio_gestor
  on public.vales for insert
  with check (gestor_id = auth.uid() and status = 'draft');

create policy vales_update_propio_gestor_borrador
  on public.vales for update
  using (gestor_id = auth.uid() and status in ('draft', 'sent'))
  with check (gestor_id = auth.uid() and status in ('draft', 'sent'));

create policy vales_update_admin
  on public.vales for update
  using (public.is_admin());

-- ============================================================
-- ÍTEMS DEL VALE
-- ============================================================
create policy vale_items_select_propio_gestor
  on public.vale_items for select
  using (
    exists (select 1 from public.vales v where v.id = vale_items.vale_id and v.gestor_id = auth.uid())
  );

create policy vale_items_select_admin
  on public.vale_items for select
  using (public.is_admin());

create policy vale_items_insert_propio_gestor
  on public.vale_items for insert
  with check (
    exists (
      select 1 from public.vales v
      where v.id = vale_items.vale_id
        and v.gestor_id = auth.uid()
        and v.status in ('draft', 'sent')
    )
  );

create policy vale_items_delete_propio_gestor
  on public.vale_items for delete
  using (
    exists (
      select 1 from public.vales v
      where v.id = vale_items.vale_id
        and v.gestor_id = auth.uid()
        and v.status = 'draft'
    )
  );

create policy vale_items_update_admin
  on public.vale_items for update
  using (public.is_admin());

create policy vale_items_delete_admin
  on public.vale_items for delete
  using (public.is_admin());

-- ============================================================
-- COMISIONES
-- No existen políticas de INSERT/UPDATE para usuarios normales:
-- las comisiones solo se generan a través de la función
-- approve_vale() (ver rpc.sql), que corre con privilegios elevados.
-- ============================================================
create policy commissions_select_propio_gestor
  on public.commissions for select
  using (gestor_id = auth.uid());

create policy commissions_select_propio_lider
  on public.commissions for select
  using (leader_id = auth.uid());

create policy commissions_select_admin
  on public.commissions for select
  using (public.is_admin());

-- ============================================================
-- PAGOS
-- ============================================================
create policy payouts_select_propio
  on public.payouts for select
  using (profile_id = auth.uid());

create policy payouts_select_admin
  on public.payouts for select
  using (public.is_admin());

create policy payouts_insert_admin
  on public.payouts for insert
  with check (public.is_admin());

-- ============================================================
-- CONFIGURACIÓN (ej. número de WhatsApp)
-- ============================================================
create policy settings_select_autenticados
  on public.settings for select
  using (auth.role() = 'authenticated');

create policy settings_update_admin
  on public.settings for update
  using (public.is_admin());
