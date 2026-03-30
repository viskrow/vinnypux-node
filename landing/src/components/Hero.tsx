import { AuthView } from '../App'

interface Props {
  onAuth: (view: AuthView) => void
}

export default function Hero({ onAuth }: Props) {
  return (
    <section className="hero">
      <div className="container">
        <div className="hero-badge">
          <span className="hero-badge-dot" />
          New · Advanced AI Engine v3.2 Released
        </div>

        <h1>
          Intelligence,<br />
          <span className="gradient-text">Delivered Instantly</span>
        </h1>

        <p className="hero-sub">
          Vinnypux AI brings the power of advanced language models to your fingertips.
          Automate workflows, generate insights, and accelerate everything you do.
        </p>

        <div className="hero-actions">
          <button className="btn btn-primary" onClick={() => onAuth('signup')}>
            Get Started — It's Free
          </button>
          <button className="btn btn-outline hero-arrow" onClick={() => onAuth('signin')}>
            Sign In <span>→</span>
          </button>
        </div>
      </div>
    </section>
  )
}
