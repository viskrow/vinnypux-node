import { Anchor, Badge, Card, Group, Stack, Text, Title } from '@mantine/core'
import { PageHeader, PageShell } from '../components/Page'
import { brand } from '../brand'

const jobs = [
  {
    title: 'Senior Go-разработчик (edge / кэш)',
    team: 'Платформа',
    location: 'Москва / удалённо',
    desc: 'Разработка кэширующего слоя и балансировки на edge-нодах. Go, gRPC, высокие нагрузки.',
  },
  {
    title: 'SRE / DevOps-инженер',
    team: 'Инфраструктура',
    location: 'Москва / удалённо',
    desc: 'Эксплуатация сети из 47 PoP: мониторинг, автоматизация, отказоустойчивость. Linux, Prometheus, Ansible.',
  },
  {
    title: 'Инженер по видео-доставке',
    team: 'Медиа',
    location: 'Удалённо',
    desc: 'HLS/DASH, транскодирование, LL-стриминг. ffmpeg, кодеки H.265/AV1, протоколы RTMP/SRT.',
  },
  {
    title: 'Менеджер по работе с клиентами',
    team: 'Продажи',
    location: 'Москва',
    desc: 'Ведение B2B-клиентов, подбор тарифов, сопровождение подключения. Опыт в IT/телеком.',
  },
]

export default function Careers() {
  return (
    <PageShell size="md">
      <PageHeader
        title="Вакансии"
        subtitle="Мы небольшая команда, которая держит сеть доставки для сотен медиа-проектов. Ищем инженеров, которым интересны высокие нагрузки и видео."
      />

      <Stack gap="md">
        {jobs.map((j) => (
          <Card key={j.title} withBorder radius="md" padding="lg" style={{ background: 'rgba(255,255,255,0.02)' }}>
            <Group justify="space-between" align="flex-start" wrap="wrap" gap="sm">
              <Stack gap={6} maw={520}>
                <Text fw={600} fz="lg">
                  {j.title}
                </Text>
                <Text c="dimmed" fz="sm">
                  {j.desc}
                </Text>
              </Stack>
              <Stack gap={6} align="flex-end">
                <Badge variant="light" color="brand" radius="sm">
                  {j.team}
                </Badge>
                <Text c="dimmed" fz="xs">
                  {j.location}
                </Text>
              </Stack>
            </Group>
          </Card>
        ))}

        <Text c="dimmed" fz="sm" mt="md">
          Не нашли подходящую вакансию? Присылайте резюме на{' '}
          <Anchor href={`mailto:${brand.emailHr}`}>{brand.emailHr}</Anchor> — рассмотрим.
        </Text>
      </Stack>
    </PageShell>
  )
}
