import { useScrollReveal } from '../hooks/useScrollReveal'

const items = [
  { value: '2.4M+',   label: 'Requests / day' },
  { value: '99.97%',  label: 'Uptime SLA' },
  { value: '<100ms',  label: 'Avg. latency' },
  { value: '180+',    label: 'Countries served' },
]

export default function Stats() {
  const ref = useScrollReveal<HTMLDivElement>()

  return (
    <section className="stats">
      <div className="container">
        <div className="stats-grid" ref={ref}>
          {items.map(({ value, label }) => (
            <div key={label} className="stat-item">
              <div className="stat-value gradient-text">{value}</div>
              <div className="stat-label">{label}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
