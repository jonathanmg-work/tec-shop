-- ============================================================
-- GESTORES SYSTEM — helpers.sql
-- Ejecuta este archivo SEGUNDO (después de schema.sql).
-- Funciones auxiliares que usan las políticas de seguridad (RLS)
-- para saber quién es quién sin caer en referencias circulares.
-- ============================================================

-- Devuelve el rol de la persona autenticada actualmente (o null si no hay sesión)
-- NOTA: se llama app_role() y no current_role() porque "current_role" es una
-- palabra reservada de Postgres y provocaría conflictos.
create or replace function public.app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- true si la persona autenticada es admin
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

-- true si la persona autenticada es líder
create or replace function public.is_leader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'leader'
  );
$$;

-- true si la persona autenticada es gestor
create or replace function public.is_gestor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'gestor'
  );
$$;

-- true si el gestor indicado pertenece a la red del líder autenticado
create or replace function public.gestor_pertenece_a_lider(p_gestor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.gestores g
    where g.id = p_gestor_id and g.leader_id = auth.uid()
  );
$$;
