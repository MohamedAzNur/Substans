async function getSessionProfile() {
  const { data: { session }, error } = await supabaseClient.auth.getSession();
  if (error || !session) return { session: null, profile: null };
  const { data: profile } = await supabaseClient.from("profiles").select("*").eq("id", session.user.id).single();
  return { session, profile };
}

function homeForRole(role) {
  if (role === "admin") return "admin.html";
  if (role === "teacher") return "teacher.html";
  if (role === "pending") return "pending.html";
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
        ["activity.html", "Aktivitetslog"],
        ["reports.html", "Rapporter"]
      ]
    },
    {
      label: "Personer og hold",
      links: [
        ["students.html", "Elever"],
        ["classes.html", "Hold"],
        ["teachers.html", "Undervisere"]
      ]
    },
    {
      label: "Planlæg undervisning",
      links: [
        ["lesson-room.html", "Lektionsrum"],
        ["curriculum.html", "Undervisningsplan"],
        ["attendance.html", "Fremmøde"],
        ["resources.html", "Materialer og lektier"]
      ]
    },
    {
      label: "Følg læringen",
      links: [
        ["quizzes.html", "Quizzer"],
        ["assignments.html", "Afleveringer"],
        ["feedback.html", "Feedback"],
        ["progress.html", "Faglig udvikling"],
        ["certificates.html", "Certifikater"]
      ]
    },
    {
      label: "Kommunikation",
      links: [
        ["messages.html", "Beskeder"],
        ["calendar.html", "Kalender"]
      ]
    },
    {
      label: "Administration",
      links: [
        ["payments.html", "Betalinger"],
        ["accounts.html", "Kontoadgang"],
        ["profile.html", "Min profil"]
      ]
    }
  ];

  const teacherMenu = [
    {
      label: "Overblik",
      links: [
        ["teacher.html", "Mit lærerbord"],
        ["notifications.html", "Notifikationer"]
      ]
    },
    {
      label: "Dagens undervisning",
      links: [
        ["lesson-room.html", "Lektionsrum"],
        ["attendance.html", "Fremmøde"],
        ["calendar.html", "Kalender"]
      ]
    },
    {
      label: "Indhold",
      links: [
        ["curriculum.html", "Undervisningsplan"],
        ["resources.html", "Materialer og lektier"],
        ["quizzes.html", "Quizzer"]
      ]
    },
    {
      label: "Følg eleverne",
      links: [
        ["assignments.html", "Afleveringer"],
        ["feedback.html", "Feedback"],
        ["progress.html", "Faglig udvikling"],
        ["certificates.html", "Certifikater"]
      ]
    },
    {
      label: "Praktisk",
      links: [
        ["messages.html", "Beskeder til hold"],
        ["profile.html", "Min profil"]
      ]
    }
  ];

  const studentMenu = [
    {
      label: "Overblik",
      links: [
        ["portal.html", "Min forside"],
        ["notifications.html", "Notifikationer"],
        ["portal.html#calendar", "Kalender"]
      ]
    },
    {
      label: "Undervisning",
      links: [
        ["lesson-room.html", "Mine lektioner"],
        ["portal.html#learning", "Materialer og lektier"],
        ["quizzes.html", "Quizzer"],
        ["assignments.html", "Mine afleveringer"]
      ]
    },
    {
      label: "Min udvikling",
      links: [
        ["portal.html#feedback", "Feedback og mål"],
        ["curriculum.html", "Min undervisningsplan"],
        ["certificates.html", "Mine certifikater"]
      ]
    },
    {
      label: "Praktisk",
      links: [
        ["portal.html#messages", "Beskeder fra Substans"],
        ["profile.html", "Min profil"]
      ]
    }
  ];

  const parentMenu = [
    {
      label: "Overblik",
      links: [
        ["portal.html", "Mit barn"],
        ["notifications.html", "Notifikationer"]
      ]
    },
    {
      label: "Barnets læring",
      links: [
        ["curriculum.html", "Undervisningsplan"],
        ["portal.html#learning", "Materialer og lektier"],
        ["quizzes.html", "Quizresultater"],
        ["assignments.html", "Afleveringsstatus"],
        ["certificates.html", "Certifikater"]
      ]
    },
    {
      label: "Opfølgning",
      links: [
        ["portal.html#feedback", "Feedback og udvikling"],
        ["portal.html#messages", "Beskeder"],
        ["portal.html#calendar", "Kalender"],
        ["portal.html#payments", "Betalinger"]
      ]
    },
    {
      label: "Konto",
      links: [
        ["profile.html", "Min profil"]
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
        ["#learning", "#feedback", "#progress", "lesson-room.html", "curriculum.html", "certificates.html", "resources.html", "quizzes.html", "assignments.html"].includes(href)
      )
    },
    {
      label: "Samarbejde",
      links: existingLinks.filter(([href]) => ["#messages", "#calendar"].includes(href))
    },
    {
      label: "Administration",
      links: existingLinks.filter(([href]) => ["#payments", "admin.html", "profile.html"].includes(href))
    }
  ].filter(section => section.links.length);

  const menuKey = role || (isTeacherNavigation ? "teacher" : (isAdminNavigation ? "admin" : "portal"));
  if (nav.dataset.menuKey === menuKey) return;
  const roleMenus = {
    admin: adminMenu,
    teacher: teacherMenu,
    student: studentMenu,
    parent: parentMenu
  };
  const menu = roleMenus[menuKey] || portalMenu;
  const currentFile = window.location.pathname.split("/").pop() || "portal.html";
  const currentHash = window.location.hash;
  const isActiveLink = href => {
    const target = new URL(href, window.location.href);
    const targetFile = target.pathname.split("/").pop() || "portal.html";
    return targetFile === currentFile && target.hash === currentHash;
  };
  const activeSectionIndex = menu.findIndex(section =>
    section.links.some(([href]) => isActiveLink(href))
  );

  nav.innerHTML = menu.map((section,index) => {
    const open = index === activeSectionIndex || (activeSectionIndex === -1 && index === 0);
    const sectionId = `nav-section-${menuKey}-${index}`;
    return `
    <div class="nav-section${open ? " is-open" : ""}">
      <button class="nav-section-toggle" type="button" aria-expanded="${open}" aria-controls="${sectionId}" data-nav-section-toggle>
        <span>${section.label}</span><span class="nav-section-chevron" aria-hidden="true">›</span>
      </button>
      <div id="${sectionId}" class="nav-section-links">
        ${section.links.map(([href, label]) => {
          const active = isActiveLink(href);
          return `<a href="${href}"${active ? ' class="active" aria-current="page"' : ""}>${label}</a>`;
        }).join("")}
      </div>
    </div>
  `;
  }).join("");
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
    const sectionToggle = event.target.closest("[data-nav-section-toggle]");
    if (sectionToggle) {
      const section = sectionToggle.closest(".nav-section");
      const willOpen = !section.classList.contains("is-open");
      nav.querySelectorAll(".nav-section").forEach(item => {
        item.classList.remove("is-open");
        item.querySelector("[data-nav-section-toggle]")?.setAttribute("aria-expanded","false");
      });
      section.classList.toggle("is-open",willOpen);
      sectionToggle.setAttribute("aria-expanded",String(willOpen));
      return;
    }
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
