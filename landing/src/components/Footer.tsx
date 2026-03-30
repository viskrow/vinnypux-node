export default function Footer() {
  const year = new Date().getFullYear()
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-inner">
          <div className="footer-logo">
            <span style={{ fontSize: '1.1rem' }}>✦</span>
            Vinnypux AI
          </div>

          <div className="footer-links">
            <a href="#">Privacy</a>
            <a href="#">Terms</a>
            <a href="#">Security</a>
            <a href="#">Status</a>
            <a href="#">Contact</a>
          </div>

          <div className="footer-copy">© {year} Vinnypux AI. All rights reserved.</div>
        </div>
      </div>
    </footer>
  )
}
