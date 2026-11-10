// SiriWave classic is self-hosted; this illustration does not access audio.
const scenes = document.querySelectorAll('[data-motion-scene]');
const container = document.querySelector('.audio-wave');
const waveformScene = container.closest('[data-motion-scene]');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const darkMode = matchMedia('(prefers-color-scheme: dark)');
let wave;
let amplitudeTimer;
let amplitudeStep = 0;
let lastSize = '';

function updateWaveform() {
  clearInterval(amplitudeTimer);
  if (!wave) return;
  if (reducedMotion.matches || document.hidden || !waveformScene.classList.contains('in-view')) {
    wave.stop();
    return;
  }
  wave.start();
  amplitudeTimer = setInterval(() => {
    wave.setAmplitude(0.82 + 0.16 * Math.sin(++amplitudeStep * 0.9));
  }, 2400);
}
function createWaveform() {
  if (!window.SiriWave) return; // The static SVG remains if the library fails.
  const {width, height} = container.getBoundingClientRect();
  if (!width || !height) return;
  wave?.dispose();
  wave = new SiriWave({
    container, width, height, style: 'ios', autostart: false,
    ratio: Math.min(devicePixelRatio || 1, 2),
    color: getComputedStyle(container).getPropertyValue('--accent').trim(),
    speed: 0.035, amplitude: 0.82, frequency: 4, lerpSpeed: 0.015,
    globalCompositeOperation: 'source-over',
    curveDefinition: [
      {attenuation: -3, lineWidth: 1.2, opacity: 0.25},
      {attenuation: 2, lineWidth: 1.5, opacity: 0.5},
      {attenuation: 1, lineWidth: 2, opacity: 1},
    ],
  });
  container.classList.add('wave-ready');
  updateWaveform();
}
const observer = new IntersectionObserver(entries => {
  for (const entry of entries) {
    entry.target.classList.toggle('in-view', entry.isIntersecting);
    if (entry.isIntersecting) entry.target.classList.add('is-visible');
  }
  updateWaveform();
}, {threshold: 0.35});
scenes.forEach(scene => observer.observe(scene));
new ResizeObserver(() => {
  const size = `${container.clientWidth}:${container.clientHeight}`;
  if (size !== lastSize) {
    lastSize = size;
    createWaveform();
  }
}).observe(container);
reducedMotion.addEventListener('change', updateWaveform);
darkMode.addEventListener('change', createWaveform);
document.addEventListener('visibilitychange', updateWaveform);
