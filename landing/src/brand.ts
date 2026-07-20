// ─────────────────────────────────────────────────────────────────────────
// Single source of truth for the cover-brand. To rename the whole site,
// change `name` here + the <title>/<meta> in index.html. Nothing else.
// (Decoy cover for the selfsteal fallback — a plausible Russian media-CDN.)
// ─────────────────────────────────────────────────────────────────────────

export const brand = {
  name: 'Streamora',
  domain: 'streamora.cloud',
  tagline: 'Доставка видео и медиа без буферизации',
  lead:
    'Платформа доставки видео поверх мульти-CDN: стриминг, VOD и объектное хранилище ' +
    'через 47 точек присутствия. Меньше 40 мс до зрителя, отдача без пиковых просадок.',

  founded: 2019,

  // Legal / requisites (RU realism layer)
  legalName: 'ООО «Стримора»',
  inn: '7726489213',
  kpp: '772601001',
  ogrn: '1217700284519',
  address: '125167, г. Москва, Ленинградский проспект, д. 39, стр. 80, этаж 5',
  director: 'Соколов Артём Игоревич',

  bank: 'ПАО «Сбербанк», г. Москва',
  bik: '044525225',
  account: '40702810400000123456',
  corrAccount: '30101810400000000225',

  emailSales: 'sales@streamora.cloud',
  emailSupport: 'support@streamora.cloud',
  emailHr: 'hr@streamora.cloud',
  phone: '+7 (495) 120-45-67',
} as const

export const stats = [
  { value: '47', label: 'точек присутствия' },
  { value: '12 Тбит/с', label: 'суммарная ёмкость' },
  { value: '99,98%', label: 'аптайм по SLA' },
  { value: '38 мс', label: 'средняя задержка' },
] as const
