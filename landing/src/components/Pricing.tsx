import { useScrollReveal } from '../hooks/useScrollReveal'
import { AuthView } from '../App'

interface Props {
  onAuth: (view: AuthView) => void
}

const plans = [
  {
    name: 'Starter',
    price: '0',
    desc: 'Perfect for personal projects and exploration.',
    featured: false,
    features: [
      '200 requests / day',
      '1 workspace',
      'GPT-4o mini access',
      'Community support',
      'REST API access',
    ],
    cta: 'Get Started Free',
    view: 'signup' as AuthView,
  },
  {
    name: 'Pro',
    price: '24',
    desc: 'For teams that move fast and ship often.',
    featured: true,
    features: [
      'Unlimited requests',
      '20 workspaces',
      'All models including GPT-4o',
      'Priority support',
      'Advanced analytics',
      'Custom system prompts',
    ],
    cta: 'Start Free Trial',
    view: 'signup' as AuthView,
  },
  {
    name: 'Enterprise',
    price: 'Custom',
    desc: 'Dedicated infrastructure with enterprise SLA.',
    featured: false,
    features: [
      'Everything in Pro',
      'Dedicated compute',
      'Custom fine-tuning',
      '99.99% uptime SLA',
      'SOC 2 Type II',
      'Dedicated account manager',
    ],
    cta: 'Contact Sales',
    view: 'signup' as AuthView,
  },
]

export default function Pricing({ onAuth }: Props) {
  const titleRef = useScrollReveal<HTMLDivElement>()

  return (
    <section className="pricing" id="pricing">
      <div className="container">
        <div className="pricing-header" ref={titleRef}>
          <div className="section-label">Pricing</div>
          <h2 className="section-title">Simple, transparent pricing</h2>
          <p className="section-sub">
            Start free, scale as you grow. No hidden fees, no surprises.
          </p>
        </div>

        <div className="pricing-grid">
          {plans.map(({ name, price, desc, featured, features, cta, view }, i) => (
            <PricingCard
              key={name}
              name={name}
              price={price}
              desc={desc}
              featured={featured}
              features={features}
              cta={cta}
              delay={i * 80}
              onAuth={() => onAuth(view)}
            />
          ))}
        </div>
      </div>
    </section>
  )
}

function PricingCard({
  name, price, desc, featured, features, cta, delay, onAuth,
}: {
  name: string; price: string; desc: string; featured: boolean
  features: string[]; cta: string; delay: number; onAuth: () => void
}) {
  const ref = useScrollReveal<HTMLDivElement>(delay)
  return (
    <div className={`pricing-card${featured ? ' featured' : ''}`} ref={ref}>
      {featured && <div className="pricing-badge">Most Popular</div>}
      <div className="pricing-name">{name}</div>
      <div className="pricing-price">
        {price === 'Custom' ? (
          <span className="amount" style={{ fontSize: '2rem' }}>Custom</span>
        ) : (
          <>
            <span style={{ fontSize: '1.4rem', color: 'var(--text-muted)', alignSelf: 'flex-start', marginTop: 8 }}>$</span>
            <span className="amount">{price}</span>
            <span className="period">/mo</span>
          </>
        )}
      </div>
      <p className="pricing-desc">{desc}</p>
      <div className="pricing-divider" />
      <ul className="pricing-features">
        {features.map(f => (
          <li key={f} className="pricing-feature">
            <span className="pricing-check on">✓</span>
            {f}
          </li>
        ))}
      </ul>
      <button
        className={`btn ${featured ? 'btn-primary' : 'btn-outline'}`}
        onClick={onAuth}
      >
        {cta}
      </button>
    </div>
  )
}
