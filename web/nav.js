// Hamburger Menu Logic
document.addEventListener('DOMContentLoaded', () => {
  const hamburger = document.querySelector('.hamburger');
  const nav = document.querySelector('.topbar nav');
  const navLinks = document.querySelectorAll('.topbar nav a');

  if (hamburger && nav) {
    hamburger.addEventListener('click', () => {
      hamburger.classList.toggle('active');
      nav.classList.toggle('nav-open');
    });

    // Close menu when a link is clicked
    navLinks.forEach(link => {
      // Don't close if they just clicked the dropdown trigger on mobile
      if (link.classList.contains('dropdown-trigger')) {
        return;
      }
      link.addEventListener('click', () => {
        hamburger.classList.remove('active');
        nav.classList.remove('nav-open');
      });
    });

    // Dropdown Toggle (Desktop & Mobile)
    const dropdownTriggers = document.querySelectorAll('.dropdown-trigger');
    dropdownTriggers.forEach(trigger => {
      trigger.addEventListener('click', (e) => {
        // Toggle the .active class on the parent .nav-dropdown
        const parent = e.target.closest('.nav-dropdown');
        if (parent) {
          parent.classList.toggle('active');
        }
      });
    });

    // Close dropdowns when clicking outside
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.nav-dropdown')) {
        document.querySelectorAll('.nav-dropdown.active').forEach(dropdown => {
          dropdown.classList.remove('active');
        });
      }
    });
  }
});
