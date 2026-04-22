// Marketing page interactivity
// Navbar offset for anchors: scroll-padding-top on html (marketing.tailwind.css)

document.addEventListener('DOMContentLoaded', function() {
  initAccordions();
  initMobileMenu();
  initSmoothScroll();
  initDeepLinkedAccordion();
});

function setAccordionExpanded(trigger, expanded) {
  const content = trigger.nextElementSibling;
  const icon = trigger.querySelector('[data-accordion-icon]');
  if (!content) return;
  trigger.setAttribute('aria-expanded', expanded ? 'true' : 'false');
  if (expanded) {
    content.style.maxHeight = content.scrollHeight + 'px';
    if (icon) icon.style.transform = 'rotate(180deg)';
  } else {
    content.style.maxHeight = '0';
    if (icon) icon.style.transform = 'rotate(0deg)';
  }
}

function closeOtherAccordionsInGroup(trigger) {
  const group = trigger.closest('[data-accordion-group]');
  if (!group) return;
  group.querySelectorAll('[data-accordion-trigger]').forEach(otherTrigger => {
    if (otherTrigger !== trigger) {
      setAccordionExpanded(otherTrigger, false);
    }
  });
}

function findAccordionTriggerForHashTarget(target) {
  if (!target) return null;
  const group = target.closest('[data-accordion-group]');
  if (!group) return null;
  let el = target;
  while (el && el !== group) {
    const trigger = el.querySelector(':scope > [data-accordion-trigger]');
    if (trigger) return trigger;
    el = el.parentElement;
  }
  return null;
}

function expandAccordionForElement(target) {
  const trigger = findAccordionTriggerForHashTarget(target);
  if (!trigger) return false;
  closeOtherAccordionsInGroup(trigger);
  setAccordionExpanded(trigger, true);
  return true;
}

function scrollTargetIntoView(el, smooth) {
  if (!el) return;
  el.scrollIntoView({
    block: 'start',
    behavior: smooth ? 'smooth' : 'instant'
  });
}

function navigateToHashTarget(hash, { smooth } = { smooth: false }) {
  if (!hash || hash === '#') return;
  let id;
  try {
    id = decodeURIComponent(hash.slice(1));
  } catch (_e) {
    return;
  }
  if (!id) return;
  const target = document.getElementById(id);
  if (!target) return;

  const expandedAccordion = expandAccordionForElement(target);
  const scroll = () => scrollTargetIntoView(target, smooth);

  if (expandedAccordion) {
    requestAnimationFrame(() => {
      requestAnimationFrame(scroll);
    });
  } else {
    scroll();
  }
}

function initAccordions() {
  document.querySelectorAll('[data-accordion-trigger]').forEach(trigger => {
    trigger.addEventListener('click', function() {
      const isExpanded = this.getAttribute('aria-expanded') === 'true';
      closeOtherAccordionsInGroup(this);
      setAccordionExpanded(this, !isExpanded);
    });
  });
}

function initDeepLinkedAccordion() {
  const pending = window.__marketingPendingHash;
  if (pending) {
    try {
      delete window.__marketingPendingHash;
    } catch (_e) {
      window.__marketingPendingHash = undefined;
    }
    navigateToHashTarget(pending, { smooth: false });
    history.replaceState(null, '', location.pathname + location.search + pending);
  } else if (window.location.hash && window.location.hash !== '#') {
    navigateToHashTarget(window.location.hash, { smooth: false });
  }

  window.addEventListener('hashchange', function() {
    navigateToHashTarget(window.location.hash, { smooth: false });
  });
}

function initMobileMenu() {
  const mobileMenuButton = document.querySelector('[data-mobile-menu-button]');
  const mobileMenu = document.querySelector('[data-mobile-menu]');

  if (mobileMenuButton && mobileMenu) {
    mobileMenuButton.addEventListener('click', function() {
      const isExpanded = this.getAttribute('aria-expanded') === 'true';
      this.setAttribute('aria-expanded', !isExpanded);
      mobileMenu.classList.toggle('hidden');
    });
  }
}

function initSmoothScroll() {
  const mobileMenuButton = document.querySelector('[data-mobile-menu-button]');
  const mobileMenu = document.querySelector('[data-mobile-menu]');

  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      if (href === '#') return;

      const targetElement = document.querySelector(href);
      if (targetElement) {
        e.preventDefault();
        history.replaceState(null, '', href);
        navigateToHashTarget(href, { smooth: true });

        if (mobileMenu && !mobileMenu.classList.contains('hidden')) {
          mobileMenu.classList.add('hidden');
          if (mobileMenuButton) mobileMenuButton.setAttribute('aria-expanded', 'false');
        }
      }
    });
  });
}
