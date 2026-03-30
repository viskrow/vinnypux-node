import { useState } from 'react'
import Navbar from './components/Navbar'
import Hero from './components/Hero'
import Features from './components/Features'
import Stats from './components/Stats'
import Pricing from './components/Pricing'
import Footer from './components/Footer'
import AuthModal from './components/AuthModal'

export type AuthView = 'signin' | 'signup'

export default function App() {
  const [authOpen, setAuthOpen] = useState(false)
  const [authView, setAuthView] = useState<AuthView>('signin')

  const openAuth = (view: AuthView = 'signin') => {
    setAuthView(view)
    setAuthOpen(true)
  }

  return (
    <>
      <div className="bg-orbs">
        <div className="orb orb-1" />
        <div className="orb orb-2" />
        <div className="orb orb-3" />
      </div>
      <Navbar onAuth={openAuth} />
      <main>
        <Hero onAuth={openAuth} />
        <Stats />
        <Features />
        <Pricing onAuth={openAuth} />
      </main>
      <Footer />
      {authOpen && (
        <AuthModal
          view={authView}
          onViewChange={setAuthView}
          onClose={() => setAuthOpen(false)}
        />
      )}
    </>
  )
}
