// ============================================================
// GESTORES SYSTEM — supabase-client.js
// ============================================================
// IMPORTANTE: pon aquí la URL y la "anon key" (clave pública)
// de TU proyecto de Supabase. Las encuentras en:
// Supabase Dashboard → Project Settings → API.
//
// La "anon key" es segura de exponer en el navegador: por eso
// existe. Toda la seguridad real vive en las políticas RLS
// (supabase/policies.sql) y en las funciones del servidor
// (supabase/rpc.sql, supabase/edge-functions/).
// NUNCA pongas aquí la "service_role key".
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
export const SUPABASE_ANON_KEY = "TU_ANON_KEY_AQUI";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});

// URL base de la Edge Function que crea usuarios (admin/líder).
// Sigue el patrón: https://TU-PROYECTO.supabase.co/functions/v1/create-user
export const CREATE_USER_FUNCTION_URL = `${SUPABASE_URL}/functions/v1/create-user`;
