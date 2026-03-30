import { useEffect, useState } from 'react'
import { AuthView } from '../App'

interface Props {
  onAuth: (view: AuthView) => void
}

export default function Navbar({ onAuth }: Props) {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`navbar${scrolled ? ' scrolled' : ''}`}>
      <div className="container">
        <div className="navbar-inner">
          <a href="/" className="navbar-logo">
            <div className="navbar-logo-icon">✦</div>
            <span>Vinnypux AI</span>
          </a>

          <div className="navbar-links">
            <a href="#features">Features</a>
            <a href="#pricing">Pricing</a>
            <a href="#docs">Docs</a>
            <a href="#blog">Blog</a>
          </div>

          <div className="navbar-actions">
            <button className="btn btn-ghost" onClick={() => onAuth('signin')}>
              Sign In
            </button>
            <button className="btn btn-primary" onClick={() => onAuth('signup')}>
              Get Started
            </button>
          </div>
        </div>
      </div>
    </nav>
  )
}
