import { useEffect, useState } from 'react'
import { Box } from '@mantine/core'
import { Outlet, useLocation } from 'react-router-dom'
import Navbar from './Navbar'
import Footer from './Footer'
import AccessModal from './AuthModal'
import { AccessContext } from '../access'

function ScrollToTop() {
  const { pathname } = useLocation()
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [pathname])
  return null
}

export default function Layout() {
  const [accessOpen, setAccessOpen] = useState(false)

  return (
    <AccessContext.Provider value={() => setAccessOpen(true)}>
      <ScrollToTop />
      <div className="bg-orbs">
        <div className="orb orb-1" />
        <div className="orb orb-2" />
        <div className="orb orb-3" />
      </div>

      <Navbar />

      <Box component="main" pos="relative" style={{ zIndex: 1 }}>
        <Outlet />
      </Box>

      <Footer />

      <AccessModal opened={accessOpen} onClose={() => setAccessOpen(false)} />
    </AccessContext.Provider>
  )
}
