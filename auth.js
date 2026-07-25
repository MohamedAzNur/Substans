async function getSessionProfile() {
  const { data: { session }, error } = await supabaseClient.auth.getSession();
  if (error || !session) return { session: null, profile: null };
  const { data: profile } = await supabaseClient.from("profiles").select("*").eq("id", session.user.id).single();
  return { session, profile };
}

async function requireRole(allowedRoles) {
  const { session, profile } = await getSessionProfile();
  if (!session) {
    window.location.replace("login.html");
    return null;
  }
  if (!profile || !allowedRoles.includes(profile.role)) {
    window.location.replace(profile?.role === "admin" ? "admin.html" : "portal.html");
    return null;
  }
  return { session, profile };
}

async function signOut() {
  await supabaseClient.auth.signOut();
  window.location.replace("login.html");
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
  })[char]);
}

function setupCampusNavigation() {
  const sidebar = document.querySelector(".sidebar");
  const nav = sidebar?.querySelector(".nav");
  const brand = sidebar?.querySelector(".brand");
  if (!sidebar || !nav || !brand || sidebar.dataset.navigationReady === "true") return;

  sidebar.dataset.navigationReady = "true";

  const adminMenu = [
    {
      label: "Overblik",
      links: [
        ["admin.html", "Ansøgninger"],
        ["reports.html", "Rapporter"]
      ]
    },
    {
      label: "Undervisning",
      links: [
        ["students.html", "Elever"],
        ["classes.html", "Hold"],
        ["teachers.html", "Undervisere"],
        ["attendance.html", "Fremmøde"],
        ["resources.html", "Materialer"],
        ["progress.html", "Udvikling"]
      ]
    },
    {
      label: "Samarbejde",
      links: [
        ["feedback.html", "Feedback"],
        ["messages.html", "Beskeder"],
        ["calendar.html", "Kalender"]
      ]
    },
    {
      label: "Administration",
      links: [
        ["payments.html", "Betalinger"],
        ["accounts.html", "Kontoadgang"]
      ]
    }
  ];

  const isAdminNavigation = Boolean(nav.querySelector('a[href="admin.html"]'))
    && Boolean(nav.querySelector('a[href="students.html"]'));

  const existingLinks = [...nav.querySelectorAll("a")].map(link => [
    link.getAttribute("href") || "#",
    link.textContent.trim()
  ]);

  const portalMenu = [
    { label: "Overblik", links: existingLinks.filter(([href]) => href === "portal.html") },
    {
      label: "Læring",
      links: existingLinks.filter(([href]) =>
        ["#learning", "#feedback", "#progress", "resources.html"].includes(href)
      )
    },
    {
      label: "Samarbejde",
      links: existingLinks.filter(([href]) => ["#messages", "#calendar"].includes(href))
    },
    {
      label: "Administration",
      links: existingLinks.filter(([href]) => ["#payments", "admin.html"].includes(href))
    }
  ].filter(section => section.links.length);

  const menu = isAdminNavigation ? adminMenu : portalMenu;
  const currentFile = window.location.pathname.split("/").pop() || "portal.html";
  const currentHash = window.location.hash;

  nav.innerHTML = menu.map(section => `
    <div class="nav-section">
      <span class="nav-label">${section.label}</span>
      ${section.links.map(([href, label]) => {
        const active = href.startsWith("#")
          ? currentHash === href
          : href === currentFile;
        return `<a href="${href}"${active ? ' class="active" aria-current="page"' : ""}>${label}</a>`;
      }).join("")}
    </div>
  `).join("");

  const menuButton = document.createElement("button");
  menuButton.type = "button";
  menuButton.className = "menu-toggle";
  menuButton.setAttribute("aria-expanded", "false");
  menuButton.setAttribute("aria-controls", "campus-navigation");
  menuButton.innerHTML = '<span class="menu-toggle-icon" aria-hidden="true"><i></i><i></i><i></i></span><span>Menu</span>';
  nav.id = "campus-navigation";
  brand.insertAdjacentElement("afterend", menuButton);
  sidebar.classList.add("has-menu-toggle");

  const closeMenu = () => {
    nav.classList.remove("is-open");
    menuButton.setAttribute("aria-expanded", "false");
  };

  menuButton.addEventListener("click", () => {
    const open = !nav.classList.contains("is-open");
    nav.classList.toggle("is-open", open);
    menuButton.setAttribute("aria-expanded", String(open));
  });

  nav.addEventListener("click", event => {
    if (event.target.closest("a") && window.matchMedia("(max-width: 900px)").matches) {
      closeMenu();
    }
  });

  document.addEventListener("keydown", event => {
    if (event.key === "Escape") closeMenu();
  });

  document.addEventListener("click", event => {
    if (
      window.matchMedia("(max-width: 900px)").matches
      && nav.classList.contains("is-open")
      && !sidebar.contains(event.target)
    ) {
      closeMenu();
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupCampusNavigation);
} else {
  setupCampusNavigation();
}
