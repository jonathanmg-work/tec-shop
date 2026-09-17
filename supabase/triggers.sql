-- ============================================================
-- GESTORES SYSTEM — triggers.sql
-- Ejecuta este archivo CUARTO.
-- Estos triggers son la razón por la que un gestor no puede
-- "editar" el precio o la comisión de un producto desde las
-- herramientas del navegador: el precio, el nombre del producto
-- y la comisión SIEMPRE se recalculan en el servidor a partir
-- del catálogo real, ignorando lo que venga del cliente.
-- ============================================================

-- ---------- Fija precio/comisión reales al insertar un ítem de vale ----------
create or replace function public.fijar_precio_y_comision_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_catalog record;
begin
  select price, commission_type, commission_value, name, is_active
    into v_catalog
    from public.catalogo_gestor
    where id = new.product_id;

  if not found or v_catalog.is_active is false then
    raise exception 'El producto seleccionado no existe o no está activo.';
  end if;

  new.unit_price := v_catalog.price;
  new.product_name := v_catalog.name;

  if v_catalog.commission_type = 'percent' then
    new.commission_amount := round(v_catalog.price * new.quantity * (v_catalog.commission_value / 100.0), 2);
  else
    new.commission_amount := round(v_catalog.commission_value * new.quantity, 2);
  end if;

  return new;
end;
$$;

create trigger trg_fijar_precio_y_comision
  before insert on public.vale_items
  for each row
  execute function public.fijar_precio_y_comision_item();

-- ---------- Recalcula el total del vale cada vez que cambian sus ítems ----------
create or replace function public.recalcular_total_vale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vale_id bigint;
  v_total numeric(10,2);
begin
  v_vale_id := coalesce(new.vale_id, old.vale_id);

  select coalesce(sum(unit_price * quantity), 0)
    into v_total
    from public.vale_items
    where vale_id = v_vale_id;

  update public.vales set total_amount = v_total where id = v_vale_id;

  return null;
end;
$$;

create trigger trg_recalcular_total_insert
  after insert on public.vale_items
  for each row
  execute function public.recalcular_total_vale();

create trigger trg_recalcular_total_update
  after update on public.vale_items
  for each row
  execute function public.recalcular_total_vale();

create trigger trg_recalcular_total_delete
  after delete on public.vale_items
  for each row
  execute function public.recalcular_total_vale();
