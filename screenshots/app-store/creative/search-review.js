  const byId = id => document.getElementById(id);
  const film = byId('film');
  const seek = byId('seek');
  const locale = byId('locale');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  function play() { film.play().catch(() => {}); }
  function timestamp(seconds) {
    const whole = Math.floor(seconds);
    return Math.floor(whole / 60) + ':' + String(whole % 60).padStart(2, '0');
  }
  function updatePlayback() {
    if (Number.isFinite(film.duration) && film.duration > 0) seek.max = film.duration;
    seek.value = film.currentTime;
    byId('time').value = timestamp(film.currentTime) + ' / ' + timestamp(Number(seek.max));
    byId('play').textContent = film.paused ? '播放' : '暂停';
  }
  for (const event of ['timeupdate', 'pause', 'play', 'loadedmetadata', 'durationchange', 'emptied']) {
    film.addEventListener(event, updatePlayback);
  }
  byId('play').addEventListener('click', () => film.paused ? play() : film.pause());
  seek.addEventListener('input', () => { if (film.readyState) film.currentTime = Number(seek.value); });
  for (const [id, target, cls] of [['wide', '.listing', 'wide'], ['crop', '.stage', 'cropped']]) {
    byId(id).addEventListener('click', () => {
      const enabled = document.querySelector(target).classList.toggle(cls);
      byId(id).setAttribute('aria-pressed', String(enabled));
    });
  }
  locale.addEventListener('change', () => {
    const playing = !film.paused;
    const position = film.currentTime;
    const base = (film.dataset.exports || 'exports/') + locale.value + '/';
    const url = base + 'moro-search-' + locale.value + '-3840x2560.mp4';
    byId('subtitle').textContent = locale.selectedOptions[0].dataset.subtitle;
    byId('original').href = url;
    const contact = byId('contact');
    if (contact) contact.href = base + 'four-pages.jpg';
    film.poster = base + 'poster.jpg';
    film.src = film.dataset.preview ? base + 'preview.mp4' : url;
    film.currentTime = position;
    if (playing) play();
  });
  for (const button of document.querySelectorAll('button[data-at]')) {
    button.addEventListener('click', () => {
      film.pause();
      film.currentTime = Number(button.dataset.at);
      updatePlayback();
    });
  }
  if (!reduceMotion) play();
