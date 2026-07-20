import { Anchor, Box, Container, Divider, Group, Stack, Text } from '@mantine/core'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import { brand } from '../brand'

type FooterLink = { label: string; to?: string; href?: string }

const cols: { title: string; links: FooterLink[] }[] = [
  {
    title: 'Продукт',
    links: [
      { label: 'Возможности', href: '/#features' },
      { label: 'Тарифы', href: '/#pricing' },
      { label: 'Статус сети', href: '/#status' },
      { label: 'Документация', to: '/docs' },
    ],
  },
  {
    title: 'Компания',
    links: [
      { label: 'О компании', to: '/about' },
      { label: 'Контакты', to: '/contacts' },
      { label: 'Вакансии', to: '/careers' },
      { label: 'Блог', to: '/blog' },
    ],
  },
  {
    title: 'Правовое',
    links: [
      { label: 'Публичная оферта', to: '/legal/offer' },
      { label: 'Политика конфиденциальности', to: '/legal/privacy' },
      { label: 'Обработка ПДн (152-ФЗ)', to: '/legal/pdn' },
      { label: 'Реквизиты', to: '/legal/requisites' },
    ],
  },
]

function FooterLinkEl({ link }: { link: FooterLink }) {
  const common = { c: 'dimmed' as const, fz: 'sm' as const, underline: 'never' as const }
  return link.to ? (
    <Anchor component={Link} to={link.to} {...common}>
      {link.label}
    </Anchor>
  ) : (
    <Anchor href={link.href} {...common}>
      {link.label}
    </Anchor>
  )
}

export default function Footer() {
  return (
    <Box component="footer" pos="relative" style={{ zIndex: 1, borderTop: '1px solid var(--mantine-color-dark-4)' }} py={54}>
      <Container size="lg">
        <Group justify="space-between" align="flex-start" wrap="wrap" gap={40}>
          <Stack gap="sm" maw={320}>
            <Anchor component={Link} to="/" underline="never" c="gray.0">
              <Logo />
            </Anchor>
            <Text c="dimmed" fz="sm" lh={1.6}>
              {brand.tagline}. Медиа-CDN и edge-инфраструктура для стриминга и VOD.
            </Text>
            <Anchor href={`mailto:${brand.emailSales}`} c="dimmed" fz="sm" mt={4}>
              {brand.emailSales}
            </Anchor>
          </Stack>

          <Group align="flex-start" gap={56} wrap="wrap">
            {cols.map((c) => (
              <Stack key={c.title} gap={12}>
                <Text fw={600} fz="sm">
                  {c.title}
                </Text>
                {c.links.map((l) => (
                  <FooterLinkEl key={l.label} link={l} />
                ))}
              </Stack>
            ))}
          </Group>
        </Group>

        <Divider my={32} />

        <Stack gap={4}>
          <Text c="dimmed" fz="xs">
            {brand.legalName} · ИНН {brand.inn} · ОГРН {brand.ogrn}
          </Text>
          <Text c="dimmed" fz="xs">
            {brand.address} · {brand.phone}
          </Text>
          <Text c="dimmed" fz="xs" mt={6}>
            © {brand.founded}—2026 {brand.name}. Все права защищены.
          </Text>
        </Stack>
      </Container>
    </Box>
  )
}
