// ============================================================
// GESTORES SYSTEM — layout.js
// Dibuja la barra lateral según el rol de quien inició sesión.
// No hay "includes" de servidor (GitHub Pages es estático), así
// que cada página llama a renderSidebar(profile, 'clave-activa').
// ============================================================

import { logout } from "./auth.js";

const NAV_BY_ROLE = {
  admin: [
    { href: "/admin/dashboard.html", label: "Dashboard", key: "dashboard" },
    { href: "/admin/vales.html", label: "Vales", key: "vales" },
    { href: "/admin/pagos.html", label: "Pagos semanales", key: "pagos" },
    { href: "/admin/usuarios.html", label: "Usuarios", key: "usuarios" },
    { href: "/admin/catalogo.html", label: "Catálogo", key: "catalogo" },
    { href: "/admin/configuracion.html", label: "Configuración", key: "configuracion" },
  ],
  leader: [
    { href: "/lider/dashboard.html", label: "Dashboard", key: "dashboard" },
    { href: "/lider/gestores.html", label: "Mis gestores", key: "gestores" },
  ],
  gestor: [
    { href: "/gestor/dashboard.html", label: "Dashboard", key: "dashboard" },
    { href: "/gestor/catalogo.html", label: "Catálogo y vale nuevo", key: "catalogo" },
    { href: "/gestor/mis-vales.html", label: "Mis vales", key: "mis-vales" },
  ],
};

const ROLE_LABEL = { admin: "Administrador", leader: "Líder", gestor: "Gestor" };

export function renderSidebar(profile, activeKey) {
  const container = document.getElementById("sidebar");
  if (!container) return;

  const items = NAV_BY_ROLE[profile.role] || [];

  container.innerHTML = `
    <div class="brand">
      Gestores &amp; Líderes
      <small>${ROLE_LABEL[profile.role] || profile.role}</small>
    </div>
    <nav>
      ${items
        .map(
          (item) =>
            `<a href="${item.href}" class="${item.key === activeKey ? "active" : ""}">${item.label}</a>`
        )
        .join("")}
    </nav>
    <div class="user-box">
      <strong>${escapeHtml(profile.full_name || profile.email)}</strong>
      ${profile.email}
      <button class="btn-logout" id="btn-logout" type="button">Cerrar sesión</button>
    </div>
  `;

  document.getElementById("btn-logout").addEventListener("click", logout);
}

export function statusBadge(status) {
  const labels = {
    draft: "Borrador",
    sent: "Enviado",
    approved: "Aprobado",
    rejected: "Rechazado",
    completed: "Completado",
    active: "Activo",
    inactive: "Suspendido",
    pending_approval: "Pendiente",
    pending: "Pendiente",
    paid: "Pagado",
  };
  return `<span class="badge badge-${status}">${labels[status] || status}</span>`;
}

export function formatMoney(value) {
  const n = Number(value || 0);
  return `$${n.toFixed(2)}`;
}

export function formatDate(value) {
  if (!value) return "—";
  return new Date(value).toLocaleString("es-PR", { dateStyle: "medium", timeStyle: "short" });
}

export function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

export function showAlert(containerId, message, type = "error") {
  const el = document.getElementById(containerId);
  if (!el) return;
  el.innerHTML = `<div class="alert alert-${type}">${escapeHtml(message)}</div>`;
}

export function clearAlert(containerId) {
  const el = document.getElementById(containerId);
  if (el) el.innerHTML = "";
}
