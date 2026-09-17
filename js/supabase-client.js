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

export const SUPABASE_URL = "https://ofpnatilodkbcsacncbo.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9mcG5hdGlsb2RrYmNzYWNuY2JvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk2NzA4ODQsImV4cCI6MjEwNTI0Njg4NH0.p9WdHR37ppOU-Vr4J36vjwBqUCIVYtC1NSLNADoTjBg";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});

// URL base de la Edge Function que crea usuarios (admin/líder).
// Sigue el patrón: https://TU-PROYECTO.supabase.co/functions/v1/create-user
export const CREATE_USER_FUNCTION_URL = `${SUPABASE_URL}/functions/v1/create-user`;
