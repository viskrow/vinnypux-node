import { Anchor, Card, Group, SimpleGrid, Stack, Text, ThemeIcon, Title } from '@mantine/core'
import { IconBuilding, IconClock, IconMail, IconPhone } from '@tabler/icons-react'
import { PageHeader, PageShell } from '../components/Page'
import { useAccess } from '../access'
import { Button } from '@mantine/core'
import { brand } from '../brand'

const items = [
  { icon: IconMail, title: 'Отдел продаж', value: brand.emailSales, href: `mailto:${brand.emailSales}` },
  { icon: IconMail, title: 'Техподдержка', value: brand.emailSupport, href: `mailto:${brand.emailSupport}` },
  { icon: IconPhone, title: 'Телефон', value: brand.phone, href: `tel:${brand.phone.replace(/[^\d+]/g, '')}` },
  { icon: IconClock, title: 'Время работы', value: 'Пн–Пт, 10:00–19:00 (МСК)' },
]

export default function Contacts() {
  const openAccess = useAccess()
  return (
    <PageShell size="md">
      <PageHeader
        title="Контакты"
        subtitle="Отдел продаж ответит в течение рабочего дня и поможет подобрать тариф. Техподдержка на связи 24/7."
      />

      <Stack gap={40}>
        <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
          {items.map((it) => (
            <Card key={it.title} withBorder radius="md" padding="lg" style={{ background: 'rgba(255,255,255,0.02)' }}>
              <Group gap="md" wrap="nowrap">
                <ThemeIcon size={42} radius="md" variant="light" color="brand">
                  <it.icon size={22} stroke={1.7} />
                </ThemeIcon>
                <Stack gap={2}>
                  <Text fz="sm" c="dimmed">
                    {it.title}
                  </Text>
                  {it.href ? (
                    <Anchor href={it.href} fw={500}>
                      {it.value}
                    </Anchor>
                  ) : (
                    <Text fw={500}>{it.value}</Text>
                  )}
                </Stack>
              </Group>
            </Card>
          ))}
        </SimpleGrid>

        <Card withBorder radius="md" padding="lg" style={{ background: 'rgba(255,255,255,0.02)' }}>
          <Group gap="md" wrap="nowrap" align="flex-start">
            <ThemeIcon size={42} radius="md" variant="light" color="brand">
              <IconBuilding size={22} stroke={1.7} />
            </ThemeIcon>
            <Stack gap={4}>
              <Text fw={600}>{brand.legalName}</Text>
              <Text c="dimmed" fz="sm">
                {brand.address}
              </Text>
              <Text c="dimmed" fz="sm">
                ИНН {brand.inn} · КПП {brand.kpp} · ОГРН {brand.ogrn}
              </Text>
            </Stack>
          </Group>
        </Card>

        <Card withBorder radius="lg" padding="xl" style={{ background: 'rgba(34,211,238,0.05)' }}>
          <Stack gap="sm" align="flex-start">
            <Title order={3} fz={{ base: 20, sm: 26 }}>
              Готовы подключиться?
            </Title>
            <Text c="dimmed">
              Оставьте заявку — откроем тестовый период на 14 дней и поможем с интеграцией.
            </Text>
            <Button mt="xs" radius="md" onClick={openAccess}>
              Запросить доступ
            </Button>
          </Stack>
        </Card>
      </Stack>
    </PageShell>
  )
}
