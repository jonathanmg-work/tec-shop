// ============================================================
// GESTORES SYSTEM — auth.js
// Funciones compartidas de sesión y control de acceso por rol.
// Cada página protegida llama a requireRole(...) al cargar.
// ============================================================

import { supabase } from "./supabase-client.js";

/**
 * Inicia sesión con email/contraseña.
 * @returns {Promise<{profile: object}>}
 */
export async function login(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(traducirErrorAuth(error.message));

  const profile = await getProfile(data.user.id);

  if (!profile) {
    await supabase.auth.signOut();
    throw new Error("Tu cuenta no tiene un perfil asociado. Contacta al administrador.");
  }

  if (profile.status === "pending_approval") {
    await supabase.auth.signOut();
    throw new Error("Tu cuenta está pendiente de aprobación por un administrador.");
  }

  if (profile.status === "inactive") {
    await supabase.auth.signOut();
    throw new Error("Tu cuenta está suspendida. Contacta al administrador.");
  }

  return { profile };
}

export async function logout() {
  await supabase.auth.signOut();
  window.location.href = "/index.html";
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function getProfile(userId) {
  const { data, error } = await supabase.from("profiles").select("*").eq("id", userId).single();
  if (error) return null;
  return data;
}

/**
 * Protege una página: exige sesión activa y (opcionalmente) un rol
 * específico. Si no se cumple, redirige a login o al panel correcto.
 * Úsalo al inicio de cada página protegida.
 *
 * @param {string[]} allowedRoles - ej. ['admin'] o ['leader','admin']
 * @returns {Promise<{user: object, profile: object}>}
 */
export async function requireRole(allowedRoles) {
  const session = await getSession();

  if (!session) {
    window.location.href = "/index.html";
    throw new Error("redirect");
  }

  const profile = await getProfile(session.user.id);

  if (!profile || profile.status !== "active") {
    await supabase.auth.signOut();
    window.location.href = "/index.html";
    throw new Error("redirect");
  }

  if (!allowedRoles.includes(profile.role)) {
    window.location.href = redirectPathForRole(profile.role);
    throw new Error("redirect");
  }

  return { user: session.user, profile };
}

export function redirectPathForRole(role) {
  if (role === "admin") return "/admin/dashboard.html";
  if (role === "leader") return "/lider/dashboard.html";
  return "/gestor/dashboard.html";
}

function traducirErrorAuth(message) {
  if (message.includes("Invalid login credentials")) {
    return "Correo o contraseña incorrectos.";
  }
  return message;
}
