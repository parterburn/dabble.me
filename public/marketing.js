// Marketing page interactivity
document.addEventListener('DOMContentLoaded', function() {
  initAccordions();
  initMobileMenu();
  initSmoothScroll();
});

function initAccordions() {
  const accordionTriggers = document.querySelectorAll('[data-accordion-trigger]');
  
  accordionTriggers.forEach(trigger => {
    trigger.addEventListener('click', function() {
      const content = this.nextElementSibling;
      const icon = this.querySelector('[data-accordion-icon]');
      const isExpanded = this.getAttribute('aria-expanded') === 'true';
      
      // Close all other accordions in the same group
      const group = this.closest('[data-accordion-group]');
      if (group) {
        group.querySelectorAll('[data-accordion-trigger]').forEach(otherTrigger => {
          if (otherTrigger !== this) {
            otherTrigger.setAttribute('aria-expanded', 'false');
            otherTrigger.nextElementSibling.style.maxHeight = '0';
            const otherIcon = otherTrigger.querySelector('[data-accordion-icon]');
            if (otherIcon) otherIcon.style.transform = 'rotate(0deg)';
          }
        });
      }
      
      // Toggle current accordion
      this.setAttribute('aria-expanded', !isExpanded);
      if (!isExpanded) {
        content.style.maxHeight = content.scrollHeight + 'px';
        if (icon) icon.style.transform = 'rotate(180deg)';
        
        // Scroll the accordion item into view after a brief delay
        const accordionItem = this.closest('.accordion-item');
        setTimeout(() => {
          accordionItem.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }, 100);
      } else {
        content.style.maxHeight = '0';
        if (icon) icon.style.transform = 'rotate(0deg)';
      }
    });
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
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      
      const targetElement = document.querySelector(targetId);
      if (targetElement) {
        e.preventDefault();
        targetElement.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
        
        // Close mobile menu if open
        if (mobileMenu && !mobileMenu.classList.contains('hidden')) {
          mobileMenu.classList.add('hidden');
          if (mobileMenuButton) mobileMenuButton.setAttribute('aria-expanded', 'false');
        }
      }
    });
  });
}
