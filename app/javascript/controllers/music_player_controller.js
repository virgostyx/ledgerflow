import { Controller } from "@hotwired/stimulus"

const STATIONS = [
  { name: "Groove Salad",  label: "Ambient · Downtempo", emoji: "🌿", url: "https://ice2.somafm.com/groovesalad-128-mp3" },
  { name: "Secret Agent",  label: "Spy Jazz · Lounge",   emoji: "🕵️", url: "https://ice2.somafm.com/secretagent-128-mp3" },
  { name: "Space Station", label: "Cosmic Ambient",      emoji: "🚀", url: "https://ice2.somafm.com/spacestation-128-mp3" },
  { name: "Lush",          label: "Indie · Chillout",    emoji: "🌸", url: "https://ice2.somafm.com/lush-128-mp3" },
  { name: "Drone Zone",    label: "Deep Ambient",        emoji: "🔮", url: "https://ice2.somafm.com/dronezone-128-mp3" },
]

// Module-level singleton: survives Turbo navigations and connect/disconnect cycles
const audio = new Audio()
audio.preload = "none"

const state = {
  playing: false,
  station: parseInt(localStorage.getItem("lf_music_station") || "0", 10),
  volume:  parseFloat(localStorage.getItem("lf_music_volume") || "0.7"),
}
audio.volume = state.volume

export default class extends Controller {
  static targets = [
    "panel", "fab", "fabRing", "vinylIcon",
    "stationName", "stationLabel", "equalizer",
    "playIcon", "pauseIcon", "volumeSlider", "stationItem",
  ]

  connect() {
    this.isOpen = false

    if (this.hasVolumeSliderTarget) {
      this.volumeSliderTarget.value = Math.round(state.volume * 100)
    }
    this._updateStationDisplay()
    this._updatePlayState()

    this._onKeydown = (e) => { if (e.key === "Escape" && this.isOpen) this.close() }
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  // ── Panel ──────────────────────────────────────────────────────────────────

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.isOpen = true
    this.panelTarget.classList.remove("hidden")
    requestAnimationFrame(() => {
      this.panelTarget.classList.add("opacity-100", "translate-y-0")
      this.panelTarget.classList.remove("opacity-0", "translate-y-2")
    })
  }

  close() {
    this.isOpen = false
    this.panelTarget.classList.add("opacity-0", "translate-y-2")
    this.panelTarget.classList.remove("opacity-100", "translate-y-0")
    setTimeout(() => this.panelTarget.classList.add("hidden"), 200)
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  togglePlay() {
    state.playing ? this._pause() : this._play()
  }

  _play() {
    const station = STATIONS[state.station]
    if (audio.src !== station.url) audio.src = station.url
    audio.play()
      .then(() => { state.playing = true; this._updatePlayState() })
      .catch((err) => console.warn("[MusicPlayer] Playback error:", err))
  }

  _pause() {
    audio.pause()
    state.playing = false
    this._updatePlayState()
  }

  // ── Station navigation ─────────────────────────────────────────────────────

  prevStation() {
    state.station = (state.station - 1 + STATIONS.length) % STATIONS.length
    this._switchStation()
  }

  nextStation() {
    state.station = (state.station + 1) % STATIONS.length
    this._switchStation()
  }

  selectStation(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (index === state.station) { this.togglePlay(); return }
    state.station = index
    this._switchStation()
  }

  _switchStation() {
    localStorage.setItem("lf_music_station", state.station)
    const wasPlaying = state.playing

    audio.pause()
    audio.src = ""
    state.playing = false
    this._updatePlayState()
    this._updateStationDisplay()

    if (wasPlaying) this._play()
  }

  // ── Volume ─────────────────────────────────────────────────────────────────

  setVolume(event) {
    const vol = event.target.value / 100
    state.volume = vol
    audio.volume = vol
    localStorage.setItem("lf_music_volume", vol)
  }

  // ── UI updates ─────────────────────────────────────────────────────────────

  _updatePlayState() {
    if (state.playing) {
      this.playIconTarget.classList.add("hidden")
      this.pauseIconTarget.classList.remove("hidden")
      this.fabRingTarget.classList.remove("hidden")
      this.equalizerTarget.classList.remove("hidden")
      this.vinylIconTarget.classList.add("music-vinyl-spin")
    } else {
      this.playIconTarget.classList.remove("hidden")
      this.pauseIconTarget.classList.add("hidden")
      this.fabRingTarget.classList.add("hidden")
      this.equalizerTarget.classList.add("hidden")
      this.vinylIconTarget.classList.remove("music-vinyl-spin")
    }
  }

  _updateStationDisplay() {
    const station = STATIONS[state.station]
    this.stationNameTarget.textContent  = `${station.emoji} ${station.name}`
    this.stationLabelTarget.textContent = station.label

    this.stationItemTargets.forEach((item, i) => {
      const active = i === state.station
      item.classList.toggle("bg-white/15",        active)
      item.classList.toggle("ring-1",             active)
      item.classList.toggle("ring-violet-400/40", active)
    })
  }
}
