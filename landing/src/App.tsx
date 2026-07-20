import { BrowserRouter, Route, Routes } from 'react-router-dom'
import Layout from './components/Layout'
import Home from './pages/Home'
import Docs from './pages/Docs'
import About from './pages/About'
import Contacts from './pages/Contacts'
import Careers from './pages/Careers'
import Blog from './pages/Blog'
import BlogPost from './pages/BlogPost'
import Legal from './pages/Legal'
import NotFound from './pages/NotFound'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Home />} />
          <Route path="docs" element={<Docs />} />
          <Route path="about" element={<About />} />
          <Route path="contacts" element={<Contacts />} />
          <Route path="careers" element={<Careers />} />
          <Route path="blog" element={<Blog />} />
          <Route path="blog/:slug" element={<BlogPost />} />
          <Route path="legal/:doc" element={<Legal />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
