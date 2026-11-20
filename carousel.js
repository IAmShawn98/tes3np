const gallery = document.querySelector('.gallery');
const slides = [...gallery.querySelectorAll('.slide')];
const previous = gallery.querySelector('.previous');
const next = gallery.querySelector('.next');
const title = gallery.querySelector('.slide-title');
const rotation = gallery.querySelector('.rotation');
const status = gallery.querySelector('[role="status"]');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

let slideIndex = 0;
let autoplay = !reducedMotion.matches;
let pointerOver = false;
let timer;
let touchStart;

function showSlide(offset, announce) {
  slides[slideIndex].setAttribute('aria-hidden', 'true');
  slideIndex = (slideIndex + offset + slides.length) % slides.length;
  const slide = slides[slideIndex];
  slide.removeAttribute('aria-hidden');
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
  if (autoplay && !pointerOver && !gallery.querySelector(':focus-visible') && !document.hidden) {
    timer = setTimeout(() => {
      showSlide(1, false);
      scheduleRotation();
    }, 5500);
  }
}

function navigate(offset) {
  showSlide(offset, true);
  scheduleRotation();
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

const slideArea = gallery.querySelector('.slides');
slideArea.addEventListener('pointerdown', (event) => {
  if (event.pointerType === 'touch' && event.isPrimary) {
    touchStart = { id: event.pointerId, x: event.clientX, y: event.clientY };
  }
});
slideArea.addEventListener('pointerup', (event) => {
  if (touchStart?.id !== event.pointerId) return;
  const x = event.clientX - touchStart.x;
  const y = event.clientY - touchStart.y;
  touchStart = undefined;
  if (Math.abs(x) > 45 && Math.abs(x) > Math.abs(y) * 1.35) navigate(x < 0 ? 1 : -1);
});
slideArea.addEventListener('pointercancel', () => { touchStart = undefined; });

slides.forEach((slide, index) => {
  if (index !== slideIndex) slide.setAttribute('aria-hidden', 'true');
  slide.hidden = false;
});
previous.hidden = false;
next.hidden = false;
rotation.hidden = false;
scheduleRotation();
