async function getSessionProfile() {
  const { data: { session }, error } = await supabaseClient.auth.getSession();
  if (error || !session) return { session: null, profile: null };
  const { data: profile } = await supabaseClient.from("profiles").select("*").eq("id", session.user.id).single();
  return { session, profile };
}

function homeForRole(role) {
  if (role === "admin") return "admin.html";
  if (role === "teacher") return "teacher.html";
  return "portal.html";
}

async function requireRole(allowedRoles) {
  const { session, profile } = await getSessionProfile();
  if (!session) {
    window.location.replace("login.html");
    return null;
  }
  if (!profile || !allowedRoles.includes(profile.role)) {
    window.location.replace(homeForRole(profile?.role));
    return null;
  }
  setupCampusNavigation(profile.role);
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

function setupCampusNavigation(role = null) {
  const sidebar = document.querySelector(".sidebar");
  const nav = sidebar?.querySelector(".nav");
  const brand = sidebar?.querySelector(".brand");
  if (!sidebar || !nav || !brand) return;

  const adminMenu = [
    {
      label: "Overblik",
      links: [
        ["admin.html", "Ansøgninger"],
        ["notifications.html", "Notifikationer"],
        ["reports.html", "Rapporter"]
      ]
    },
    {
      label: "Undervisning",
      links: [
        ["students.html", "Elever"],
        ["classes.html", "Hold"],
        ["teachers.html", "Undervisere"],
        ["lesson-room.html", "Lektionsrum"],
        ["curriculum.html", "Undervisningsplan"],
        ["attendance.html", "Fremmøde"],
        ["resources.html", "Materialer"],
        ["quizzes.html", "Quizzer"],
        ["assignments.html", "Afleveringer"],
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

  const teacherMenu = [
    {
      label: "Overblik",
      links: [
        ["teacher.html", "Mit lærerbord"],
        ["notifications.html", "Notifikationer"],
        ["portal.html", "Mit Campus"]
      ]
    },
    {
      label: "Undervisning",
      links: [
        ["lesson-room.html", "Lektionsrum"],
        ["curriculum.html", "Undervisningsplan"],
        ["attendance.html", "Fremmøde"],
        ["resources.html", "Materialer og lektier"],
        ["quizzes.html", "Quizzer og læringstjek"],
        ["assignments.html", "Afleveringer"],
        ["progress.html", "Faglig udvikling"],
        ["calendar.html", "Kalender"]
      ]
    },
    {
      label: "Samarbejde",
      links: [
        ["feedback.html", "Feedback"],
        ["messages.html", "Beskeder"]
      ]
    }
  ];

  const originalLinks = [...nav.querySelectorAll("a")];
  const isAdminNavigation = Boolean(nav.querySelector('a[href="admin.html"]'))
    && Boolean(nav.querySelector('a[href="students.html"]'));
  const isTeacherNavigation = Boolean(nav.querySelector('a[href="teacher.html"]'));

  const existingLinks = originalLinks.map(link => [
    link.getAttribute("href") || "#",
    link.textContent.trim()
  ]);

  const portalMenu = [
    { label: "Overblik", links: existingLinks.filter(([href]) => ["portal.html", "notifications.html"].includes(href)) },
    {
      label: "Læring",
      links: existingLinks.filter(([href]) =>
        ["#learning", "#feedback", "#progress", "lesson-room.html", "curriculum.html", "resources.html", "quizzes.html", "assignments.html"].includes(href)
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

  const menuKey = role || (isTeacherNavigation ? "teacher" : (isAdminNavigation ? "admin" : "portal"));
  if (nav.dataset.menuKey === menuKey) return;
  const menu = menuKey === "admin" ? adminMenu : (menuKey === "teacher" ? teacherMenu : portalMenu);
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
  nav.dataset.menuKey = menuKey;

  nav.id = "campus-navigation";
  if (sidebar.dataset.navigationReady === "true") return;
  sidebar.dataset.navigationReady = "true";

  const menuButton = document.createElement("button");
  menuButton.type = "button";
  menuButton.className = "menu-toggle";
  menuButton.setAttribute("aria-expanded", "false");
  menuButton.setAttribute("aria-controls", "campus-navigation");
  menuButton.innerHTML = '<span class="menu-toggle-icon" aria-hidden="true"><i></i><i></i><i></i></span><span>Menu</span>';
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
