import { Box, Card, Container, SimpleGrid, Stack, Text, ThemeIcon, Title } from '@mantine/core'
import {
  IconBroadcast,
  IconMovie,
  IconBolt,
  IconDatabase,
  IconTransform,
  IconApi,
} from '@tabler/icons-react'

const features = [
  {
    icon: IconBroadcast,
    title: 'Live-стриминг',
    desc: 'Приём по RTMP / SRT / WebRTC, раздача в HLS и LL-DASH. Задержка от 2 секунд, авто-битрейт под канал зрителя.',
  },
  {
    icon: IconMovie,
    title: 'VOD-доставка',
    desc: 'Хранение и отдача видео-по-запросу с edge-кэшированием. Догрев популярного контента, мгновенный старт воспроизведения.',
  },
  {
    icon: IconBolt,
    title: 'Мульти-CDN и edge',
    desc: 'Агрегируем несколько CDN-сетей и собственные узлы — 47 точек присутствия по РФ и СНГ. Автовыбор лучшего маршрута и отказоустойчивость: если один CDN просел, трафик уходит на другой.',
  },
  {
    icon: IconDatabase,
    title: 'Объектное хранилище',
    desc: 'S3-совместимое хранилище для исходников и сегментов. Оплата за объём, без лимита на количество файлов.',
  },
  {
    icon: IconTransform,
    title: 'Транскодирование',
    desc: 'Перекодирование в лету в нужные профили и кодеки (H.264 / H.265 / AV1). Водяные знаки, нарезка на сегменты.',
  },
  {
    icon: IconApi,
    title: 'API и SDK',
    desc: 'REST-API, вебхуки и SDK для управления потоками, кэшем и статистикой. Инвалидация кэша и метрики в реальном времени.',
  },
]

export default function Features() {
  return (
    <Box component="section" id="features" py={{ base: 70, sm: 100 }}>
      <Container size="lg">
        <Stack gap={14} mb={54}>
          <Text tt="uppercase" fw={600} fz="xs" c="brand.4" style={{ letterSpacing: '0.12em' }}>
            Возможности
          </Text>
          <Title order={2} fz={{ base: 30, sm: 44 }} maw={620} style={{ letterSpacing: '-0.02em' }}>
            Всё для доставки видео в одной платформе
          </Title>
          <Text c="dimmed" fz="lg" maw={560}>
            От приёма прямого эфира до отдачи готовых сегментов на ближайшей к зрителю ноде —
            поверх мульти-CDN, без десятка отдельных договоров.
          </Text>
        </Stack>

        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          {features.map((f) => (
            <Card
              key={f.title}
              padding="xl"
              radius="lg"
              withBorder
              style={{
                background: 'rgba(255,255,255,0.02)',
                transition: 'transform 0.25s ease, border-color 0.25s ease',
              }}
            >
              <ThemeIcon size={48} radius="md" variant="light" color="brand" mb="md">
                <f.icon size={26} stroke={1.7} />
              </ThemeIcon>
              <Text fw={700} fz="lg" mb={8}>
                {f.title}
              </Text>
              <Text c="dimmed" fz="sm" lh={1.6}>
                {f.desc}
              </Text>
            </Card>
          ))}
        </SimpleGrid>
      </Container>
    </Box>
  )
}
