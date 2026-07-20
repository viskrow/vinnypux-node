import { Card, SimpleGrid, Stack, Text, Timeline, Title } from '@mantine/core'
import { PageHeader, PageShell } from '../components/Page'
import { brand, stats } from '../brand'

export default function About() {
  return (
    <PageShell size="md">
      <PageHeader
        title="О компании"
        subtitle={`${brand.legalName} строит сеть доставки медиа-контента с ${brand.founded} года.`}
      />

      <Stack gap={44}>
        <Text c="dimmed" fz="lg" lh={1.75}>
          {brand.name} — российская платформа доставки медиа. Мы отдаём видео наших клиентов —
          прямые трансляции, видео-по-запросу и стриминговые сервисы — маршрутизируя трафик
          поверх нескольких CDN-сетей и собственных узлов. Наша задача — чтобы зритель получал
          картинку без буферизации, а бизнес не переплачивал за трафик, не держал собственный
          парк серверов и не заключал договоры с десятком CDN по отдельности.
        </Text>

        <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="md">
          {stats.map((s) => (
            <Card key={s.label} withBorder radius="md" padding="lg" style={{ background: 'rgba(255,255,255,0.02)' }}>
              <Text fz={26} fw={800} className="grad-text" lh={1}>
                {s.value}
              </Text>
              <Text c="dimmed" fz="sm" mt={6}>
                {s.label}
              </Text>
            </Card>
          ))}
        </SimpleGrid>

        <Stack gap="md">
          <Title order={3} fz={{ base: 20, sm: 26 }}>
            Как мы росли
          </Title>
          <Timeline active={4} bulletSize={16} lineWidth={2} color="brand">
            <Timeline.Item title="2019 — запуск">
              <Text c="dimmed" fz="sm">
                Первые две точки присутствия в Москве. Раздача статики и VOD для медиа-проектов.
              </Text>
            </Timeline.Item>
            <Timeline.Item title="2021 — live-стриминг">
              <Text c="dimmed" fz="sm">
                Приём RTMP/SRT и раздача HLS. Подключены первые стриминговые площадки.
              </Text>
            </Timeline.Item>
            <Timeline.Item title="2023 — регионы и СНГ">
              <Text c="dimmed" fz="sm">
                Сеть выросла до 40+ PoP по РФ и СНГ. Запущено объектное хранилище.
              </Text>
            </Timeline.Item>
            <Timeline.Item title="2025 — low-latency">
              <Text c="dimmed" fz="sm">
                LL-HLS и WebRTC-доставка, транскодирование в лету, задержка эфира от 2 секунд.
              </Text>
            </Timeline.Item>
            <Timeline.Item title="Сегодня">
              <Text c="dimmed" fz="sm">
                47 точек присутствия, 12 Тбит/с суммарной ёмкости, аптайм 99,98% по SLA.
              </Text>
            </Timeline.Item>
          </Timeline>
        </Stack>
      </Stack>
    </PageShell>
  )
}
