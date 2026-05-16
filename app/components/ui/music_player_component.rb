class Ui::MusicPlayerComponent < ViewComponent::Base
  STATIONS = [
    { name: "Groove Salad",  label: "Ambient · Downtempo", emoji: "🌿", index: 0 },
    { name: "Secret Agent",  label: "Spy Jazz · Lounge",   emoji: "🕵️", index: 1 },
    { name: "Space Station", label: "Cosmic Ambient",      emoji: "🚀", index: 2 },
    { name: "Lush",          label: "Indie · Chillout",    emoji: "🌸", index: 3 },
    { name: "Drone Zone",    label: "Deep Ambient",        emoji: "🔮", index: 4 }
  ].freeze
end
