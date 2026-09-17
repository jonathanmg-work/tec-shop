// ============================================================
// GESTORES SYSTEM — Edge Function: create-user
// ============================================================
// Esta es la ÚNICA pieza del sistema que corre en un servidor
// (no en el navegador) porque crear una cuenta de autenticación
// requiere la "service_role key" de Supabase, que NUNCA debe
// exponerse en el frontend (le da acceso total, saltándose toda
// la seguridad por fila / RLS).
//
// Flujo:
//   - Admin crea líderes o gestores directamente -> quedan 'active'.
//   - Líder crea gestores para su propia red -> quedan 'pending_approval'
//     hasta que el admin los apruebe (cambiando status a 'active'
//     desde el panel, lo cual sí puede hacerse por RLS normal).
//
// Despliegue (ver README.md para el paso a paso):
//   supabase functions deploy create-user
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...
// ============================================================

import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Método no permitido." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const callerToken = authHeader.replace("Bearer ", "");

    if (!callerToken) {
      return jsonResponse({ error: "No autenticado." }, 401);
    }

    // Cliente "como el usuario que llama", solo para verificar quién es.
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${callerToken}` } },
    });

    const { data: callerUser, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerUser?.user) {
      return jsonResponse({ error: "Sesión inválida." }, 401);
    }

    const { data: callerProfile, error: profileErr } = await callerClient
      .from("profiles")
      .select("id, role, status")
      .eq("id", callerUser.user.id)
      .single();

    if (profileErr || !callerProfile) {
      return jsonResponse({ error: "No se encontró el perfil de quien llama." }, 403);
    }

    if (callerProfile.role !== "admin" && callerProfile.role !== "leader") {
      return jsonResponse({ error: "No tienes permiso para crear cuentas." }, 403);
    }

    const body = await req.json();
    const { email, password, full_name, role, override_percentage, is_vip } = body as {
      email: string;
      password: string;
      full_name: string;
      role: "leader" | "gestor";
      override_percentage?: number;
      is_vip?: boolean;
    };

    if (!email || !password || !full_name || !role) {
      return jsonResponse({ error: "Faltan campos obligatorios (email, password, full_name, role)." }, 400);
    }

    if (password.length < 8) {
      return jsonResponse({ error: "La contraseña debe tener al menos 8 caracteres." }, 400);
    }

    // Un líder solo puede crear gestores para SU PROPIA red.
    if (callerProfile.role === "leader" && role !== "gestor") {
      return jsonResponse({ error: "Un líder solo puede crear cuentas de gestor." }, 403);
    }

    // Cliente con privilegios de administrador (service role), solo dentro
    // de este servidor — jamás se envía esta key al navegador.
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (createErr || !created?.user) {
      return jsonResponse({ error: createErr?.message ?? "No se pudo crear el usuario." }, 400);
    }

    const newUserId = created.user.id;
    const isCreatedByLeader = callerProfile.role === "leader";
    const initialStatus = isCreatedByLeader ? "pending_approval" : "active";

    const { error: profileInsertErr } = await adminClient.from("profiles").insert({
      id: newUserId,
      email,
      full_name,
      role,
      status: initialStatus,
    });

    if (profileInsertErr) {
      // Revertir la creación del usuario de auth si falla el perfil, para no dejar huérfanos.
      await adminClient.auth.admin.deleteUser(newUserId);
      return jsonResponse({ error: `No se pudo crear el perfil: ${profileInsertErr.message}` }, 400);
    }

    if (role === "leader") {
      const { error: leaderErr } = await adminClient.from("leaders").insert({
        id: newUserId,
        override_percentage: override_percentage ?? 10,
      });
      if (leaderErr) {
        return jsonResponse({ error: `Usuario creado, pero falló leaders: ${leaderErr.message}` }, 500);
      }
    } else {
      const { error: gestorErr } = await adminClient.from("gestores").insert({
        id: newUserId,
        leader_id: isCreatedByLeader ? callerProfile.id : null,
        is_vip: is_vip ?? false,
      });
      if (gestorErr) {
        return jsonResponse({ error: `Usuario creado, pero falló gestores: ${gestorErr.message}` }, 500);
      }
    }

    return jsonResponse({
      success: true,
      user_id: newUserId,
      status: initialStatus,
      message: isCreatedByLeader
        ? "Gestor creado. Queda pendiente de aprobación del administrador."
        : "Cuenta creada y activa.",
    });
  } catch (err) {
    return jsonResponse({ error: `Error inesperado: ${(err as Error).message}` }, 500);
  }
});
