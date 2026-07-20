import { Badge, Box, Button, Card, Container, Divider, Group, List, Stack, Text, ThemeIcon, Title } from '@mantine/core'
import { IconCheck } from '@tabler/icons-react'
import { useAccess } from '../access'

const plans = [
  {
    name: 'Старт',
    price: '4 900',
    unit: '₽ / мес',
    desc: 'Для небольших проектов и запуска эфиров.',
    featured: false,
    cta: 'Запросить доступ',
    features: [
      '2 ТБ трафика включено',
      'До 5 одновременных потоков',
      'HLS / DASH раздача',
      'Объектное хранилище 100 ГБ',
      'Поддержка по email',
    ],
  },
  {
    name: 'Бизнес',
    price: '19 900',
    unit: '₽ / мес',
    desc: 'Для медиа и сервисов с постоянной нагрузкой.',
    featured: true,
    cta: 'Запросить доступ',
    features: [
      '15 ТБ трафика включено',
      'Без лимита одновременных потоков',
      'Транскодирование в лету',
      'Объектное хранилище 1 ТБ',
      'Приоритетная поддержка 24/7',
      'API, вебхуки и метрики',
    ],
  },
  {
    name: 'Энтерпрайз',
    price: 'Индивидуально',
    unit: '',
    desc: 'Выделенная ёмкость и SLA под ваш проект.',
    featured: false,
    cta: 'Связаться с отделом продаж',
    features: [
      'Всё из тарифа «Бизнес»',
      'Выделенные PoP и ёмкость',
      'Персональный аккаунт-менеджер',
      'SLA 99,98% с компенсацией',
      'Приватное подключение и BYOC',
    ],
  },
]

export default function Pricing() {
  const openAccess = useAccess()
  return (
    <Box component="section" id="pricing" py={{ base: 70, sm: 100 }}>
      <Container size="lg">
        <Stack gap={14} align="center" ta="center" mb={54}>
          <Text tt="uppercase" fw={600} fz="xs" c="brand.4" style={{ letterSpacing: '0.12em' }}>
            Тарифы
          </Text>
          <Title order={2} fz={{ base: 30, sm: 44 }} style={{ letterSpacing: '-0.02em' }}>
            Прозрачные цены, оплата в рублях
          </Title>
          <Text c="dimmed" fz="lg" maw={520}>
            Трафик сверх пакета — от 0,9 ₽/ГБ. Без скрытых платежей, счёт и закрывающие документы.
          </Text>
        </Stack>

        <Group align="stretch" gap="md" justify="center" wrap="wrap">
          {plans.map((p) => (
            <Card
              key={p.name}
              padding="xl"
              radius="lg"
              withBorder
              w={{ base: '100%', sm: 320 }}
              maw={360}
              style={{
                position: 'relative',
                background: p.featured ? 'rgba(34, 211, 238, 0.06)' : 'rgba(255,255,255,0.02)',
                borderColor: p.featured ? 'var(--mantine-color-brand-7)' : undefined,
              }}
            >
              {p.featured && (
                <Badge
                  color="brand"
                  variant="filled"
                  radius="xl"
                  style={{ position: 'absolute', top: -12, left: '50%', transform: 'translateX(-50%)' }}
                >
                  Популярный
                </Badge>
              )}

              <Text tt="uppercase" fw={600} fz="xs" c="dimmed" style={{ letterSpacing: '0.08em' }}>
                {p.name}
              </Text>

              <Group gap={6} align="baseline" mt={10} mb={4}>
                <Text fz={p.price.length > 8 ? 26 : 34} fw={800} style={{ letterSpacing: '-0.03em' }}>
                  {p.price}
                </Text>
                {p.unit && (
                  <Text c="dimmed" fz="sm">
                    {p.unit}
                  </Text>
                )}
              </Group>

              <Text c="dimmed" fz="sm" mih={40}>
                {p.desc}
              </Text>

              <Divider my="md" />

              <List
                spacing={10}
                fz="sm"
                c="dimmed"
                center
                icon={
                  <ThemeIcon color="brand" variant="light" size={18} radius="xl">
                    <IconCheck size={12} stroke={2.6} />
                  </ThemeIcon>
                }
              >
                {p.features.map((f) => (
                  <List.Item key={f}>{f}</List.Item>
                ))}
              </List>

              <Button
                fullWidth
                mt="xl"
                radius="md"
                variant={p.featured ? 'filled' : 'default'}
                onClick={openAccess}
              >
                {p.cta}
              </Button>
            </Card>
          ))}
        </Group>
      </Container>
    </Box>
  )
}
