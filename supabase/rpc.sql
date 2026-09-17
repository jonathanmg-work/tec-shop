-- ============================================================
-- GESTORES SYSTEM — rpc.sql
-- Ejecuta este archivo QUINTO (el último de las migraciones).
-- Funciones que el frontend llama con supabase.rpc('nombre', {...}).
-- Cada una revisa el rol de quien llama ANTES de hacer nada,
-- incluso siendo security definer, porque estas funciones corren
-- con privilegios elevados y no deben confiar en el frontend.
-- ============================================================

-- ============================================================
-- enviar_vale: gestor pasa su vale de 'draft' a 'sent'
-- (existe como RPC además de permitirlo por RLS directo, para
-- poder validar que el vale tenga al menos un ítem)
-- ============================================================
create or replace function public.enviar_vale(p_vale_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_items_count int;
  v_owner uuid;
  v_status text;
begin
  select gestor_id, status into v_owner, v_status from public.vales where id = p_vale_id;

  if v_owner is null then
    raise exception 'Vale no encontrado.';
  end if;

  if v_owner <> auth.uid() then
    raise exception 'No tienes permiso sobre este vale.';
  end if;

  if v_status <> 'draft' then
    raise exception 'Solo se pueden enviar vales en estado borrador.';
  end if;

  select count(*) into v_items_count from public.vale_items where vale_id = p_vale_id;
  if v_items_count = 0 then
    raise exception 'El vale no tiene productos. Agrega al menos uno antes de enviarlo.';
  end if;

  update public.vales
    set status = 'sent', sent_at = now()
    where id = p_vale_id;
end;
$$;

-- ============================================================
-- approve_vale: SOLO ADMIN. Aprueba el vale y genera la comisión.
-- ============================================================
create or replace function public.approve_vale(p_vale_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_gestor_id uuid;
  v_gestor record;
  v_leader record;
  v_gestor_commission numeric(10,2);
  v_leader_commission numeric(10,2) := 0;
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede aprobar vales.';
  end if;

  select status, gestor_id into v_status, v_gestor_id
    from public.vales where id = p_vale_id for update;

  if v_status is null then
    raise exception 'Vale no encontrado.';
  end if;

  if v_status <> 'sent' then
    raise exception 'Solo se pueden aprobar vales en estado "enviado".';
  end if;

  select id, leader_id, is_vip into v_gestor
    from public.gestores where id = v_gestor_id;

  select coalesce(sum(commission_amount), 0) into v_gestor_commission
    from public.vale_items where vale_id = p_vale_id;

  if v_gestor.is_vip is false and v_gestor.leader_id is not null then
    select id, override_percentage into v_leader
      from public.leaders where id = v_gestor.leader_id;

    if found then
      v_leader_commission := round(v_gestor_commission * (v_leader.override_percentage / 100.0), 2);
    end if;
  end if;

  insert into public.commissions (vale_id, gestor_id, leader_id, gestor_commission, leader_commission, status)
  values (
    p_vale_id,
    v_gestor_id,
    case when v_gestor.is_vip then null else v_gestor.leader_id end,
    v_gestor_commission,
    case when v_gestor.is_vip then 0 else v_leader_commission end,
    'pending'
  );

  update public.vales
    set status = 'approved', approved_at = now()
    where id = p_vale_id;
end;
$$;

-- ============================================================
-- reject_vale: SOLO ADMIN. Rechaza el vale con un motivo.
-- ============================================================
create or replace function public.reject_vale(p_vale_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede rechazar vales.';
  end if;

  select status into v_status from public.vales where id = p_vale_id for update;

  if v_status is null then
    raise exception 'Vale no encontrado.';
  end if;

  if v_status <> 'sent' then
    raise exception 'Solo se pueden rechazar vales en estado "enviado".';
  end if;

  update public.vales
    set status = 'rejected', rejected_at = now(), rejection_reason = p_reason
    where id = p_vale_id;
end;
$$;

-- ============================================================
-- complete_vale: SOLO ADMIN. Marca el vale y su comisión como
-- pagados en efectivo.
-- ============================================================
create or replace function public.complete_vale(p_vale_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede marcar vales como completados.';
  end if;

  select status into v_status from public.vales where id = p_vale_id for update;

  if v_status is null then
    raise exception 'Vale no encontrado.';
  end if;

  if v_status <> 'approved' then
    raise exception 'Solo se pueden completar vales ya aprobados.';
  end if;

  update public.vales
    set status = 'completed', completed_at = now()
    where id = p_vale_id;

  update public.commissions
    set status = 'paid', paid_at = now()
    where vale_id = p_vale_id;
end;
$$;

-- ============================================================
-- get_lider_vales: SOLO LÍDER. Devuelve los vales de su red,
-- SIN datos de cliente (nombre, teléfono, dirección quedan
-- fuera a propósito).
-- ============================================================
create or replace function public.get_lider_vales()
returns table (
  id bigint,
  vale_number text,
  gestor_id uuid,
  gestor_nombre text,
  delivery_method text,
  total_amount numeric,
  status text,
  created_at timestamptz,
  approved_at timestamptz,
  completed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.id,
    v.vale_number,
    v.gestor_id,
    p.full_name as gestor_nombre,
    v.delivery_method,
    v.total_amount,
    v.status,
    v.created_at,
    v.approved_at,
    v.completed_at
  from public.vales v
  join public.gestores g on g.id = v.gestor_id
  join public.profiles p on p.id = g.id
  where g.leader_id = auth.uid()
    and public.is_leader();
$$;

-- ============================================================
-- get_lider_resumen_gestores: SOLO LÍDER. Resumen de ventas y
-- comisión generada por cada gestor de su red.
-- ============================================================
create or replace function public.get_lider_resumen_gestores()
returns table (
  gestor_id uuid,
  gestor_nombre text,
  is_vip boolean,
  total_vendido numeric,
  comision_generada_lider numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id as gestor_id,
    p.full_name as gestor_nombre,
    g.is_vip,
    coalesce(sum(v.total_amount) filter (where v.status in ('approved', 'completed')), 0) as total_vendido,
    coalesce(sum(c.leader_commission) filter (where c.status in ('pending', 'paid')), 0) as comision_generada_lider
  from public.gestores g
  join public.profiles p on p.id = g.id
  left join public.vales v on v.gestor_id = g.id
  left join public.commissions c on c.vale_id = v.id
  where g.leader_id = auth.uid()
    and public.is_leader()
  group by g.id, p.full_name, g.is_vip;
$$;

-- ============================================================
-- get_weekly_payouts: SOLO ADMIN. Comisiones pendientes de pago
-- dentro de un rango de fechas (por defecto, la semana actual).
-- ============================================================
create or replace function public.get_weekly_payouts(p_start date default null, p_end date default null)
returns table (
  profile_id uuid,
  full_name text,
  role text,
  monto_pendiente numeric,
  cantidad_vales bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date := coalesce(p_start, date_trunc('week', now())::date);
  v_end date := coalesce(p_end, (date_trunc('week', now()) + interval '6 days')::date);
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede ver el panel de pagos.';
  end if;

  return query
  with gestor_amounts as (
    select c.gestor_id as profile_id, sum(c.gestor_commission) as monto, count(*) as cantidad
    from public.commissions c
    join public.vales v on v.id = c.vale_id
    where c.status = 'pending'
      and v.approved_at::date between v_start and v_end
    group by c.gestor_id
  ),
  leader_amounts as (
    select c.leader_id as profile_id, sum(c.leader_commission) as monto, count(*) as cantidad
    from public.commissions c
    join public.vales v on v.id = c.vale_id
    where c.status = 'pending'
      and c.leader_id is not null
      and v.approved_at::date between v_start and v_end
    group by c.leader_id
  ),
  combined as (
    select * from gestor_amounts
    union all
    select * from leader_amounts
  )
  select
    p.id as profile_id,
    p.full_name,
    p.role,
    sum(c.monto)::numeric as monto_pendiente,
    sum(c.cantidad)::bigint as cantidad_vales
  from combined c
  join public.profiles p on p.id = c.profile_id
  group by p.id, p.full_name, p.role
  order by monto_pendiente desc;
end;
$$;

-- ============================================================
-- get_weekly_payout_detalle: SOLO ADMIN. Vales que componen el
-- monto pendiente de una persona específica.
-- ============================================================
create or replace function public.get_weekly_payout_detalle(p_profile_id uuid, p_start date default null, p_end date default null)
returns table (
  vale_id bigint,
  vale_number text,
  monto numeric,
  rol_en_este_vale text,
  approved_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start date := coalesce(p_start, date_trunc('week', now())::date);
  v_end date := coalesce(p_end, (date_trunc('week', now()) + interval '6 days')::date);
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede ver el detalle de pagos.';
  end if;

  return query
  select v.id, v.vale_number, c.gestor_commission, 'gestor'::text, v.approved_at
  from public.commissions c
  join public.vales v on v.id = c.vale_id
  where c.status = 'pending' and c.gestor_id = p_profile_id
    and v.approved_at::date between v_start and v_end
  union all
  select v.id, v.vale_number, c.leader_commission, 'lider'::text, v.approved_at
  from public.commissions c
  join public.vales v on v.id = c.vale_id
  where c.status = 'pending' and c.leader_id = p_profile_id
    and v.approved_at::date between v_start and v_end
  order by approved_at desc;
end;
$$;
