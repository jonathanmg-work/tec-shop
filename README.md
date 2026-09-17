# Sistema de Gestores y Líderes

Sistema de gestión de fuerza de ventas con tres roles (**Administrador**, **Líder**, **Gestor**), catálogo propio de gestores, generación de vales, envío por WhatsApp, cálculo automático de comisiones con lógica VIP/override, y panel de pagos semanales.

**Arquitectura:** frontend estático (HTML/CSS/JS, sin frameworks ni build) alojado en **GitHub Pages** + backend **Supabase** (Postgres, Auth, RLS, Edge Functions).

---

## 1. Por qué esta arquitectura

GitHub Pages solo sirve archivos estáticos, así que toda la lógica sensible vive en Supabase:

| Riesgo | Cómo se resuelve |
|---|---|
| Gestor intenta ver vales de otros gestores | Políticas RLS en Postgres (`policies.sql`) — filtradas en el servidor |
| Líder intenta ver datos de clientes | Los líderes **no** tienen acceso a la tabla `vales`; consultan `get_lider_vales()`, que no devuelve nombre/teléfono/dirección |
| Gestor edita el precio o su comisión desde la consola del navegador | Triggers (`triggers.sql`) recalculan precio y comisión desde el catálogo real, ignorando lo que envíe el cliente |
| Alguien se auto-aprueba un vale | `approve_vale()` verifica que quien llama sea admin antes de hacer nada |
| Exponer claves con permisos totales | El frontend solo usa la `anon key` (pública por diseño). La `service_role key` vive únicamente como secreto en la Edge Function |

---

## 2. Instalación paso a paso

### Paso 1 — Crear el proyecto en Supabase

1. Entra a [supabase.com](https://supabase.com) y crea una cuenta (plan gratuito).
2. Crea un proyecto nuevo. Guarda la contraseña de la base de datos.
3. Espera 1-2 minutos a que el proyecto termine de aprovisionarse.

### Paso 2 — Crear las tablas y la seguridad

En el dashboard de Supabase, ve a **SQL Editor** y ejecuta los archivos de la carpeta `supabase/` **en este orden exacto** (copia y pega el contenido de cada uno, uno a la vez):

1. `schema.sql` — tablas
2. `helpers.sql` — funciones de rol
3. `policies.sql` — seguridad por fila (RLS)
4. `triggers.sql` — cálculo de precios/comisiones en el servidor
5. `rpc.sql` — funciones de aprobación, paneles y pagos

> El orden importa: cada archivo depende del anterior.

### Paso 3 — Crear tu cuenta de administrador

1. En Supabase ve a **Authentication → Users → Add user**.
2. Crea tu usuario con correo y contraseña (marca "Auto Confirm User").
3. Copia el **UUID** del usuario recién creado.
4. Vuelve al **SQL Editor** y ejecuta (reemplazando los valores):

```sql
insert into public.profiles (id, email, full_name, role, status)
values ('PEGA-AQUI-EL-UUID', 'tucorreo@ejemplo.com', 'Tu Nombre', 'admin', 'active');
```

Esta es la única cuenta que se crea a mano. Todas las demás se crean desde el panel.

### Paso 4 — Desplegar la Edge Function (creación de cuentas)

Necesitas el [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
npm install -g supabase
supabase login
supabase link --project-ref TU-PROJECT-REF

# Copia la carpeta de la función al lugar que espera el CLI
mkdir -p supabase/functions
cp -r supabase/edge-functions/create-user supabase/functions/

supabase functions deploy create-user
```

Las variables `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya están disponibles automáticamente dentro de las Edge Functions de Supabase, así que no necesitas configurarlas manualmente.

> Si prefieres no usar el CLI: en el dashboard, **Edge Functions → Deploy a new function**, nómbrala `create-user` y pega el contenido de `supabase/edge-functions/create-user/index.ts`.

### Paso 5 — Conectar el frontend con tu proyecto

Abre `js/supabase-client.js` y reemplaza:

```js
export const SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
export const SUPABASE_ANON_KEY = "TU_ANON_KEY_AQUI";
```

Ambos valores están en Supabase → **Project Settings → API**.

### Paso 6 — Publicar en GitHub Pages

1. Crea un repositorio en GitHub y sube todo el contenido de esta carpeta.
2. En el repo: **Settings → Pages**.
3. En "Source" elige **Deploy from a branch**, rama `main`, carpeta `/ (root)`.
4. Guarda. En 1-2 minutos tu sistema estará en `https://TU-USUARIO.github.io/TU-REPO/`.

> **Importante:** si publicas en un subdirectorio (`usuario.github.io/mi-repo/`), las rutas absolutas como `/admin/dashboard.html` no funcionarán. Tienes dos opciones: usar un dominio propio apuntando a la raíz, o buscar y reemplazar en `js/auth.js` y `js/layout.js` las rutas `/admin/`, `/lider/`, `/gestor/` e `/index.html` por `/TU-REPO/admin/`, etc.

### Paso 7 — Configuración inicial dentro del sistema

Entra con tu cuenta de admin y:

1. **Configuración** → pon el número de WhatsApp de administración.
2. **Catálogo** → crea los productos que venderán los gestores, con su comisión.
3. **Usuarios** → crea líderes y gestores.

---

## 3. Cómo funciona cada rol

### Gestor
1. Inicia sesión → ve su dashboard con comisión pendiente y cobrada.
2. **Catálogo y vale nuevo**: agrega productos al carrito, llena datos del cliente y método de entrega.
3. Pulsa **Generar vale** → se crea el vale, pasa a estado `enviado` y aparece el botón de WhatsApp con el mensaje ya armado.
4. **Mis vales**: historial con el estado de cada uno.

### Líder
1. Ve el total vendido por su red y su comisión (override) acumulada.
2. **Mis gestores**: resumen por gestor y creación de cuentas nuevas (quedan pendientes de aprobación del admin).
3. Nunca ve nombre, teléfono ni dirección de clientes.

### Administrador
1. **Vales**: 4 pestañas (pendientes, aprobados, completados, rechazados). Puede ver el detalle, editar los datos del cliente antes de aprobar, aprobar, rechazar con motivo, o marcar como completado cuando paga en efectivo.
2. **Pagos semanales**: suma de comisiones pendientes del rango de fechas, desglose por persona, detalle de qué vales componen cada monto, y registro del pago en efectivo.
3. **Usuarios**: crear líderes/gestores, aprobar cuentas creadas por líderes, marcar gestores como VIP, suspender y reactivar.
4. **Catálogo** y **Configuración**.

---

## 4. Lógica de comisiones

Al aprobar un vale, `approve_vale()` calcula:

1. **Comisión del gestor** = suma de la comisión de cada ítem (porcentaje del precio o monto fijo, según defina el producto en el catálogo).
2. **Comisión del líder (override)**:
   - Si el gestor es **VIP** → el líder gana **$0** (el gestor se queda con todo).
   - Si el gestor es normal y tiene líder → `comisión_gestor × (override_del_líder / 100)`.
   - Si no tiene líder → no hay override.

**Ejemplo:** producto de $100 con 10% de comisión, gestor normal con líder al 10%:
- Gestor gana $10 · Líder gana $1.
- Si ese mismo gestor fuera VIP: gestor gana $10 · líder gana $0.

---

## 5. Estados de un vale

```
borrador → enviado → aprobado → completado
                   ↘ rechazado
```

- **borrador**: creado, aún sin enviar (dura segundos; el sistema lo envía automáticamente al generarlo).
- **enviado**: pendiente de aprobación del admin.
- **aprobado**: comisiones generadas, pendientes de pago en efectivo.
- **completado**: pago en efectivo realizado (la comisión pasa a `pagada` y sale del panel de pagos pendientes).
- **rechazado**: con motivo registrado.

---

## 6. Notas importantes y limitaciones conocidas

- **Registrar un pago** en el panel de pagos semanales guarda el historial del efectivo entregado, pero lo que saca una comisión de la lista de pendientes es marcar el vale como **Completado** en la pestaña de Aprobados. Son dos acciones distintas a propósito: una es el registro contable, la otra es el cierre del vale.
- **Contraseñas temporales**: al crear una cuenta, tú defines la contraseña y se la pasas a la persona. Si quieres que puedan cambiarla, activa el flujo de recuperación de contraseña en Supabase → Authentication → Email Templates.
- **Eliminar productos del catálogo** falla si ya fueron usados en vales (por integridad referencial). En ese caso desactívalos con el check "Producto activo" en vez de borrarlos — los vales antiguos conservan el nombre y precio con el que se vendieron.
- **Plan gratuito de Supabase**: los proyectos sin actividad durante 7 días se pausan; basta con reactivarlos desde el dashboard.

---

## 7. Estructura de archivos

```
index.html                 Login
css/style.css              Estilos de todo el panel
js/
  supabase-client.js       ← AQUÍ pones tu URL y anon key
  auth.js                  Login, logout, guardias por rol
  layout.js                Barra lateral y utilidades de formato
gestor/
  dashboard.html           Resumen de ventas y comisiones
  catalogo.html            Catálogo + carrito + generar vale + WhatsApp
  mis-vales.html           Historial de vales
lider/
  dashboard.html           Resumen de la red
  gestores.html            Gestores de su red + crear cuentas
admin/
  dashboard.html           Panel general
  vales.html               Aprobar / rechazar / editar / completar
  pagos.html               Pagos semanales por persona
  usuarios.html            Crear y administrar cuentas
  catalogo.html            CRUD del catálogo de gestores
  configuracion.html       WhatsApp y overrides
supabase/
  schema.sql               1. Tablas
  helpers.sql              2. Funciones de rol
  policies.sql             3. Seguridad por fila (RLS)
  triggers.sql             4. Cálculo de precios/comisiones
  rpc.sql                  5. Aprobaciones, paneles, pagos
  edge-functions/
    create-user/index.ts   Creación segura de cuentas
```
