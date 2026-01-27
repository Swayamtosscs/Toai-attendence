// ============================================
// MICROSOFT STORE STYLE DASHBOARD JAVASCRIPT
// Premium Hard UI/UX Interactions
// ============================================

// DOM Elements
const sidebar = document.getElementById('sidebar');
const sidebarToggle = document.getElementById('sidebarToggle');
const menuBtn = document.getElementById('menuBtn');
const navLinks = document.querySelectorAll('.nav-link');
const navItems = document.querySelectorAll('.nav-item');

// ============================================
// SIDEBAR TOGGLE FUNCTIONALITY
// ============================================

sidebarToggle?.addEventListener('click', () => {
    sidebar.classList.toggle('collapsed');
    localStorage.setItem('sidebarCollapsed', sidebar.classList.contains('collapsed'));
});

menuBtn?.addEventListener('click', () => {
    if (window.innerWidth <= 768) {
        sidebar.classList.toggle('active');
    } else {
        sidebar.classList.toggle('collapsed');
        localStorage.setItem('sidebarCollapsed', sidebar.classList.contains('collapsed'));
    }
});

// Load sidebar state from localStorage
const sidebarState = localStorage.getItem('sidebarCollapsed');
if (sidebarState === 'true') {
    sidebar.classList.add('collapsed');
}

// ============================================
// NAVIGATION ACTIVE STATE
// ============================================

navLinks.forEach(link => {
    link.addEventListener('click', (e) => {
        // Remove active class from all items
        navItems.forEach(item => item.classList.remove('active'));
        
        // Add active class to clicked item
        const parent = link.closest('.nav-item');
        if (parent) {
            parent.classList.add('active');
        }
        
        // Handle smooth scroll for anchor links
        const href = link.getAttribute('href');
        if (href.startsWith('#')) {
            e.preventDefault();
            const targetId = href.substring(1);
            const targetElement = document.getElementById(targetId);
            
            if (targetElement) {
                const offsetTop = targetElement.offsetTop - 80;
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        }
        
        // Close mobile sidebar
        if (window.innerWidth <= 768) {
            sidebar.classList.remove('active');
        }
    });
});

// ============================================
// SCROLL ANIMATIONS
// ============================================

const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

// Observe cards for animation
document.querySelectorAll('.stat-card, .feature-card, .screenshot-card').forEach(card => {
    card.style.opacity = '0';
    card.style.transform = 'translateY(20px)';
    card.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
    observer.observe(card);
});

// ============================================
// CARD HOVER EFFECTS
// ============================================

const cards = document.querySelectorAll('.stat-card, .feature-card, .screenshot-card');

cards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        
        const rotateX = (y - centerY) / 20;
        const rotateY = (centerX - x) / 20;
        
        card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-4px)`;
    });
    
    card.addEventListener('mouseleave', () => {
        card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0) translateY(0)';
    });
});

// ============================================
// STAT COUNTER ANIMATION
// ============================================

const animateCounter = (element, target, duration = 2000) => {
    let start = 0;
    const increment = target / (duration / 16);
    
    const updateCounter = () => {
        start += increment;
        if (start < target) {
            if (target.toString().includes('K')) {
                element.textContent = Math.floor(start) + 'K+';
            } else if (target.toString().includes('%')) {
                element.textContent = start.toFixed(1) + '%';
            } else if (target.toString().includes('+')) {
                element.textContent = Math.floor(start) + '+';
            } else {
                element.textContent = Math.floor(start);
            }
            requestAnimationFrame(updateCounter);
        } else {
            element.textContent = target;
        }
    };
    
    updateCounter();
};

const statValues = document.querySelectorAll('.stat-value');
const statsObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting && !entry.target.classList.contains('animated')) {
            entry.target.classList.add('animated');
            const text = entry.target.textContent;
            if (text.includes('K')) {
                const num = parseInt(text);
                animateCounter(entry.target, num + 'K+');
            } else if (text.includes('%')) {
                const num = parseFloat(text);
                animateCounter(entry.target, num.toFixed(1) + '%');
            } else if (text.includes('+')) {
                const num = parseInt(text);
                animateCounter(entry.target, num + '+');
            } else {
                const num = parseInt(text);
                animateCounter(entry.target, num);
            }
        }
    });
}, { threshold: 0.5 });

statValues.forEach(stat => {
    statsObserver.observe(stat);
});

// ============================================
// HEADER SCROLL EFFECT
// ============================================

let lastScroll = 0;
const header = document.querySelector('.dashboard-header');

window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    
    if (currentScroll > 100) {
        header.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.12)';
    } else {
        header.style.boxShadow = '0 1px 2px rgba(0, 0, 0, 0.04)';
    }
    
    lastScroll = currentScroll;
});

// ============================================
// SEARCH FUNCTIONALITY
// ============================================

const searchInput = document.querySelector('.search-input');
if (searchInput) {
    searchInput.addEventListener('focus', () => {
        searchInput.parentElement.style.boxShadow = '0 0 0 3px rgba(0, 120, 212, 0.1)';
    });
    
    searchInput.addEventListener('blur', () => {
        searchInput.parentElement.style.boxShadow = 'none';
    });
}

// ============================================
// BUTTON INTERACTIONS
// ============================================

const buttons = document.querySelectorAll('.btn, .btn-upgrade, .header-icon-btn');

buttons.forEach(button => {
    button.addEventListener('click', function(e) {
        // Ripple effect
        const ripple = document.createElement('span');
        const rect = this.getBoundingClientRect();
        const size = Math.max(rect.width, rect.height);
        const x = e.clientX - rect.left - size / 2;
        const y = e.clientY - rect.top - size / 2;
        
        ripple.style.width = ripple.style.height = size + 'px';
        ripple.style.left = x + 'px';
        ripple.style.top = y + 'px';
        ripple.style.position = 'absolute';
        ripple.style.borderRadius = '50%';
        ripple.style.background = 'rgba(255, 255, 255, 0.3)';
        ripple.style.transform = 'scale(0)';
        ripple.style.animation = 'ripple 0.6s ease-out';
        ripple.style.pointerEvents = 'none';
        
        this.style.position = 'relative';
        this.style.overflow = 'hidden';
        this.appendChild(ripple);
        
        setTimeout(() => ripple.remove(), 600);
    });
});

// Add ripple animation
const style = document.createElement('style');
style.textContent = `
    @keyframes ripple {
        to {
            transform: scale(4);
            opacity: 0;
        }
    }
`;
document.head.appendChild(style);

// ============================================
// RESPONSIVE HANDLING
// ============================================

let resizeTimer;
window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
        if (window.innerWidth > 768) {
            sidebar.classList.remove('active');
        }
    }, 250);
});

// Close sidebar when clicking outside on mobile
document.addEventListener('click', (e) => {
    if (window.innerWidth <= 768) {
        if (!sidebar.contains(e.target) && !menuBtn.contains(e.target)) {
            sidebar.classList.remove('active');
        }
    }
});

// ============================================
// KEYBOARD SHORTCUTS
// ============================================

document.addEventListener('keydown', (e) => {
    // Toggle sidebar with Ctrl/Cmd + B
    if ((e.ctrlKey || e.metaKey) && e.key === 'b') {
        e.preventDefault();
        sidebar.classList.toggle('collapsed');
        localStorage.setItem('sidebarCollapsed', sidebar.classList.contains('collapsed'));
    }
    
    // Close mobile sidebar with Escape
    if (e.key === 'Escape' && window.innerWidth <= 768) {
        sidebar.classList.remove('active');
    }
});

// ============================================
// SMOOTH SCROLLING
// ============================================

document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        const href = this.getAttribute('href');
        if (href !== '#') {
            e.preventDefault();
            const target = document.querySelector(href);
            if (target) {
                const offsetTop = target.offsetTop - 80;
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        }
    });
});

// ============================================
// LAZY LOADING IMAGES
// ============================================

const imageObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            const img = entry.target;
            img.style.opacity = '0';
            img.style.transition = 'opacity 0.5s ease';
            
            if (img.complete) {
                img.style.opacity = '1';
            } else {
                img.addEventListener('load', () => {
                    img.style.opacity = '1';
                });
            }
            
            imageObserver.unobserve(img);
        }
    });
}, { threshold: 0.1 });

document.querySelectorAll('img').forEach(img => {
    imageObserver.observe(img);
});

// ============================================
// PERFORMANCE OPTIMIZATION
// ============================================

// Throttle scroll events
let ticking = false;
const optimizedScroll = () => {
    if (!ticking) {
        window.requestAnimationFrame(() => {
            ticking = false;
        });
        ticking = true;
    }
};

window.addEventListener('scroll', optimizedScroll, { passive: true });

// ============================================
// DARK MODE - ALWAYS ENABLED
// ============================================

// Set dark mode as default and always enabled
const html = document.documentElement;
html.setAttribute('data-theme', 'dark');

// ============================================
// CONSOLE MESSAGE
// ============================================

console.log('%c🚀 ToAI Attendance Dashboard', 'font-size: 20px; font-weight: bold; color: #0078d4;');
console.log('%cMicrosoft Store Style Premium UI/UX', 'font-size: 14px; color: #605e5c;');
console.log('%cBuilt with ❤️ for modern teams', 'font-size: 12px; color: #8a8886;');
