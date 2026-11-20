const gallery = document.querySelector('.gallery');
const slideArea = gallery.querySelector('.slides');
const slides = [...gallery.querySelectorAll('.slide')];
const slideLinks = slides.map((slide) => slide.querySelector('.slide-link'));
const imageLoads = new Map();
const previous = gallery.querySelector('.previous');
const next = gallery.querySelector('.next');
const title = gallery.querySelector('.slide-title');
const rotation = gallery.querySelector('.rotation');
const status = gallery.querySelector('[role="status"]');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

let slideIndex = 0;
let requestedIndex = 0;
let navigationId = 0;
let navigating = false;
let autoplay = !reducedMotion.matches;
let pointerOver = false;
let timer;
let touchStart;
let suppressSwipeClick = false;

function offsetSlide(index, offset) {
  return (index + offset + slides.length) % slides.length;
}

function loadSlide(index, priority = 'auto') {
  const link = slideLinks[index];
  let image = link.querySelector('img');
  if (!image) {
    const template = slides[index].querySelector('template');
    const fragment = document.importNode(template.content, true);
    image = fragment.querySelector('img');
    image.setAttribute('fetchpriority', priority);
    link.append(fragment);
  } else if (priority === 'auto') {
    image.removeAttribute('fetchpriority');
  }

  if (imageLoads.has(index)) return imageLoads.get(index);

  const pending = image.decode()
    .catch(() => {
      image.removeAttribute('srcset');
      image.src = link.href;
      return image.decode();
    })
    .catch((error) => {
      if (index !== slideIndex) image.remove();
      throw error;
    })
    .finally(() => imageLoads.delete(index));
  imageLoads.set(index, pending);
  return pending;
}

function preloadNext() {
  if (!document.hidden) {
    loadSlide(offsetSlide(slideIndex, 1), 'low').catch(() => {});
  }
}

function showSlide(index, announce) {
  const previousSlide = slides[slideIndex];
  const previousLink = slideLinks[slideIndex];
  const moveFocus = document.activeElement === previousLink;
  slideIndex = index;
  const slide = slides[slideIndex];
  slide.removeAttribute('aria-hidden');
  slideLinks[index].removeAttribute('tabindex');
  if (moveFocus) slideLinks[index].focus({ preventScroll: true });
  previousLink.tabIndex = -1;
  previousSlide.setAttribute('aria-hidden', 'true');
  title.textContent = slide.dataset.title;
  if (announce) {
    status.textContent = title.textContent + ', screenshot ' + (slideIndex + 1) + ' of ' + slides.length;
  }
}

function scheduleRotation() {
  clearTimeout(timer);
  const rotationLabel = autoplay ? 'Pause slideshow' : 'Play slideshow';
  rotation.setAttribute('aria-label', rotationLabel);
  rotation.title = rotationLabel;
  rotation.toggleAttribute('data-paused', !autoplay);
  if (autoplay && !navigating && !pointerOver && !gallery.querySelector(':focus-visible') && !document.hidden) {
    timer = setTimeout(() => navigate(1, false), 5500);
  }
}

async function navigate(offset, announce = true) {
  clearTimeout(timer);
  const index = offsetSlide(requestedIndex, offset);
  const id = ++navigationId;
  requestedIndex = index;
  navigating = index !== slideIndex;
  if (!navigating) {
    scheduleRotation();
    return;
  }

  try {
    await loadSlide(index);
    if (id === navigationId) {
      showSlide(index, announce);
      preloadNext();
    }
  } catch {
    if (id === navigationId) {
      requestedIndex = slideIndex;
      autoplay = false;
      status.textContent = 'The screenshot could not load. Try again.';
    }
  } finally {
    if (id === navigationId) {
      navigating = false;
      scheduleRotation();
    }
  }
}

previous.addEventListener('click', () => navigate(-1));
next.addEventListener('click', () => navigate(1));
rotation.addEventListener('click', () => {
  autoplay = !autoplay;
  scheduleRotation();
});
gallery.addEventListener('keydown', (event) => {
  if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
    event.preventDefault();
    navigate(event.key === 'ArrowLeft' ? -1 : 1);
  }
});
gallery.addEventListener('pointerenter', (event) => {
  if (event.pointerType === 'mouse') {
    pointerOver = true;
    scheduleRotation();
  }
});
gallery.addEventListener('pointerleave', (event) => {
  if (event.pointerType === 'mouse') {
    pointerOver = false;
    scheduleRotation();
  }
});
gallery.addEventListener('focusin', scheduleRotation);
gallery.addEventListener('focusout', () => setTimeout(scheduleRotation, 0));
document.addEventListener('visibilitychange', scheduleRotation);
reducedMotion.addEventListener('change', (event) => {
  autoplay = !event.matches;
  scheduleRotation();
});

slideArea.addEventListener('pointerdown', (event) => {
  if (!event.isPrimary) return;
  suppressSwipeClick = false;
  if (event.pointerType === 'touch') {
    touchStart = { id: event.pointerId, x: event.clientX, y: event.clientY };
  }
});
slideArea.addEventListener('pointerup', (event) => {
  if (touchStart?.id !== event.pointerId) return;
  const x = event.clientX - touchStart.x;
  const y = event.clientY - touchStart.y;
  touchStart = undefined;
  if (Math.abs(x) > 45 && Math.abs(x) > Math.abs(y) * 1.35) {
    suppressSwipeClick = true;
    navigate(x < 0 ? 1 : -1);
  }
});
slideArea.addEventListener('pointercancel', () => { touchStart = undefined; });
slideArea.addEventListener('click', (event) => {
  if (suppressSwipeClick && event.detail > 0) {
    event.preventDefault();
    suppressSwipeClick = false;
  }
});

slides.forEach((slide, index) => {
  if (index !== slideIndex) slide.setAttribute('aria-hidden', 'true');
  slide.hidden = false;
});
previous.hidden = false;
next.hidden = false;
rotation.hidden = false;
scheduleRotation();
loadSlide(0).catch(() => {}).then(() => {
  if (slideIndex === 0 && !navigating) preloadNext();
});
