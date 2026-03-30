import { useScrollReveal } from '../hooks/useScrollReveal'

const features = [
  {
    icon: '⚡',
    color: 'rgba(251, 191, 36, 0.15)',
    title: 'Instant Responses',
    desc: 'Multi-model inference pipeline with real-time context understanding. Sub-100ms p95 latency across all regions.',
  },
  {
    icon: '🛡️',
    color: 'rgba(34, 211, 238, 0.12)',
    title: 'Zero-Knowledge Privacy',
    desc: 'End-to-end encryption with zero-knowledge architecture. Your prompts and data never leave your control.',
  },
  {
    icon: '🔄',
    color: 'rgba(139, 92, 246, 0.15)',
    title: 'Seamless Integration',
    desc: 'REST API, GraphQL, and native SDKs for Python, TypeScript, Go and Rust. Drop-in replacement for existing workflows.',
  },
  {
    icon: '🌐',
    color: 'rgba(52, 211, 153, 0.12)',
    title: 'Global Infrastructure',
    desc: 'Distributed across 40+ edge nodes worldwide. Automatic failover and region-based routing for peak performance.',
  },
]

export default function Features() {
  const titleRef = useScrollReveal<HTMLDivElement>()

  return (
    <section className="features" id="features">
      <div className="container">
        <div className="features-header" ref={titleRef}>
          <div className="section-label">Capabilities</div>
          <h2 className="section-title">
            Everything you need<br />to ship faster
          </h2>
          <p className="section-sub">
            Purpose-built tools that integrate into your stack and scale with your team.
          </p>
        </div>

        <div className="features-grid">
          {features.map(({ icon, color, title, desc }, i) => (
            <FeatureCard key={title} icon={icon} color={color} title={title} desc={desc} delay={i * 80} />
          ))}
        </div>
      </div>
    </section>
  )
}

function FeatureCard({
  icon, color, title, desc, delay,
}: {
  icon: string; color: string; title: string; desc: string; delay: number
}) {
  const ref = useScrollReveal<HTMLDivElement>(delay)
  return (
    <div className="feature-card" ref={ref}>
      <div className="feature-icon" style={{ background: color }}>{icon}</div>
      <h3>{title}</h3>
      <p>{desc}</p>
    </div>
  )
}
