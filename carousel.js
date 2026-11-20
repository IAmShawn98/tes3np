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
const supportsFocusVisible = window.CSS && CSS.supports('selector(:focus-visible)');
const useTouchEvents = 'ontouchstart' in window;

let slideIndex = 0;
let requestedIndex = 0;
let navigationId = 0;
let navigating = false;
let autoplay = !reducedMotion.matches;
let pointerOver = false;
let timer;
let outgoingSlide;
let outgoingCleanup;
let swipe;
let suppressSwipeClick = false;
let wheelTime = -Infinity;
let wheelDistance = 0;
let wheelNavigated = false;

function offsetSlide(index, offset) {
  return (index + offset + slides.length) % slides.length;
}

function readyImage(image) {
  // Image.decode() rejects on some browsers before load completes. A load
  // event is enough to display the preview; decoding is not a navigation gate.
  return new Promise((resolve, reject) => {
    if (image.complete) {
      if (image.naturalWidth > 0) resolve();
      else reject(new Error('The screenshot could not load.'));
      return;
    }
    function finish(event) {
      image.removeEventListener('load', finish);
      image.removeEventListener('error', finish);
      if (event.type === 'load' && image.naturalWidth > 0) resolve();
      else reject(new Error('The screenshot could not load.'));
    }
    image.addEventListener('load', finish);
    image.addEventListener('error', finish);
  });
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

  const pending = readyImage(image)
    .catch(() => {
      image.removeAttribute('srcset');
      image.removeAttribute('sizes');
      image.src = link.href;
      return readyImage(image);
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

function clearOutgoingSlide() {
  clearTimeout(outgoingCleanup);
  if (outgoingSlide) outgoingSlide.classList.remove('is-outgoing');
  outgoingSlide = undefined;
}

function showSlide(index, announce) {
  const previousSlide = slides[slideIndex];
  const previousLink = slideLinks[slideIndex];
  const moveFocus = document.activeElement === previousLink;
  clearOutgoingSlide();
  if (!reducedMotion.matches) {
    outgoingSlide = previousSlide;
    outgoingSlide.classList.add('is-outgoing');
    // transitionend is not reliable when the tab is hidden or rendering is
    // suspended. Always remove the outgoing layer after the fade duration.
    outgoingCleanup = setTimeout(clearOutgoingSlide, 1350);
  }
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
  if (autoplay) rotation.removeAttribute('data-paused');
  else rotation.setAttribute('data-paused', '');
  const focused = document.activeElement;
  const keyboardFocus = gallery.contains(focused) && (!supportsFocusVisible || (focused.matches && focused.matches(':focus-visible')));
  if (autoplay && !navigating && !pointerOver && !swipe && !keyboardFocus && !document.hidden) {
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
function updateMotionPreference(event) {
  autoplay = !event.matches;
  if (event.matches) clearOutgoingSlide();
  scheduleRotation();
}
if (typeof reducedMotion.addEventListener === 'function') {
  reducedMotion.addEventListener('change', updateMotionPreference);
} else {
  reducedMotion.addListener(updateMotionPreference);
}

slideArea.addEventListener('transitionend', (event) => {
  if (event.target === slides[slideIndex] && event.propertyName === 'opacity') clearOutgoingSlide();
});

function horizontalGesture(x, y) {
  return Math.abs(x) > Math.abs(y) * 1.35;
}

function startSwipe(id, x, y) {
  suppressSwipeClick = false;
  swipe = { id, x, y };
  scheduleRotation();
}

function cancelSwipe() {
  if (!swipe) return;
  swipe = undefined;
  scheduleRotation();
}

function finishSwipe(id, x, y) {
  if (!swipe || swipe.id !== id) return false;
  const deltaX = x - swipe.x;
  const deltaY = y - swipe.y;
  const shouldNavigate = swipe.axis !== 'vertical' && Math.abs(deltaX) > 45 && horizontalGesture(deltaX, deltaY);
  swipe = undefined;
  if (shouldNavigate) {
    suppressSwipeClick = true;
    navigate(deltaX < 0 ? 1 : -1);
  } else {
    scheduleRotation();
  }
  return shouldNavigate;
}

slideArea.addEventListener('touchstart', (event) => {
  if (event.touches.length !== 1) {
    cancelSwipe();
    return;
  }
  const touch = event.touches[0];
  startSwipe(touch.identifier, touch.clientX, touch.clientY);
}, { passive: true });
slideArea.addEventListener('touchmove', (event) => {
  if (!swipe) return;
  if (event.touches.length !== 1) {
    cancelSwipe();
    return;
  }
  const touch = event.touches[0];
  if (touch.identifier !== swipe.id) return;
  const x = touch.clientX - swipe.x;
  const y = touch.clientY - swipe.y;
  if (!swipe.axis && Math.max(Math.abs(x), Math.abs(y)) > 8) {
    swipe.axis = horizontalGesture(x, y) ? 'horizontal' : 'vertical';
  }
  if (swipe.axis === 'horizontal' && event.cancelable) event.preventDefault();
}, { passive: false });
slideArea.addEventListener('touchend', (event) => {
  if (event.touches.length) {
    cancelSwipe();
    return;
  }
  const touch = event.changedTouches[0];
  if (touch && finishSwipe(touch.identifier, touch.clientX, touch.clientY) && event.cancelable) {
    event.preventDefault();
  }
}, { passive: false });
slideArea.addEventListener('touchcancel', cancelSwipe);

slideArea.addEventListener('pointerdown', (event) => {
  if (!event.isPrimary) return;
  suppressSwipeClick = false;
  if (event.pointerType === 'pen' || (event.pointerType === 'touch' && !useTouchEvents)) {
    startSwipe(event.pointerId, event.clientX, event.clientY);
  }
});
slideArea.addEventListener('pointerup', (event) => {
  if (event.pointerType === 'pen' || (event.pointerType === 'touch' && !useTouchEvents)) {
    finishSwipe(event.pointerId, event.clientX, event.clientY);
  }
});
slideArea.addEventListener('pointercancel', (event) => {
  if (event.pointerType === 'pen' || (event.pointerType === 'touch' && !useTouchEvents)) cancelSwipe();
});
slideArea.addEventListener('click', (event) => {
  if (suppressSwipeClick && event.detail > 0) {
    event.preventDefault();
    suppressSwipeClick = false;
  }
});

slideArea.addEventListener('wheel', (event) => {
  if (event.ctrlKey || event.metaKey) return;
  const mode = event.deltaMode;
  const horizontal = event.shiftKey ? (event.deltaX || event.deltaY) : event.deltaX;
  if (!horizontal || (!event.shiftKey && Math.abs(horizontal) <= Math.abs(event.deltaY))) return;
  if (event.cancelable) event.preventDefault();
  // Trackpads emit a burst of wheel events, including trailing momentum.
  if (event.timeStamp - wheelTime > 180) {
    wheelDistance = 0;
    wheelNavigated = false;
  }
  wheelTime = event.timeStamp;
  if (wheelNavigated) return;
  wheelDistance += horizontal;
  const threshold = mode === 0 ? 40 : mode === 1 ? 2 : 1;
  if (Math.abs(wheelDistance) >= threshold) {
    wheelNavigated = true;
    navigate(wheelDistance > 0 ? 1 : -1);
  }
}, { passive: false });

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
