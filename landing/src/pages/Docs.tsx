import { Anchor, Card, Code, List, Stack, Text, Title } from '@mantine/core'
import { PageHeader, PageShell } from '../components/Page'
import { brand } from '../brand'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Stack gap="sm">
      <Title order={3} fz={{ base: 20, sm: 24 }}>
        {title}
      </Title>
      {children}
    </Stack>
  )
}

export default function Docs() {
  return (
    <PageShell size="md">
      <PageHeader
        title="Документация"
        subtitle="Подключение к сети доставки, загрузка контента, live-стриминг и управление кэшем через REST-API."
      />

      <Stack gap={44}>
        <Section title="Быстрый старт">
          <Text c="dimmed" lh={1.7}>
            После активации аккаунта в личном кабинете создаётся ресурс — точка раздачи с
            привязкой к вашему origin. CDN автоматически проксирует и кэширует контент на
            ближайших к зрителю нодах. Базовый URL API:
          </Text>
          <Code block>https://api.{brand.domain}/v1</Code>
        </Section>

        <Section title="Аутентификация">
          <Text c="dimmed" lh={1.7}>
            Все запросы подписываются ключом из раздела «API-ключи» личного кабинета.
            Ключ передаётся в заголовке <Code>Authorization</Code>:
          </Text>
          <Code block>{`curl https://api.${brand.domain}/v1/resources \\
  -H "Authorization: Bearer sk_live_xxxxxxxxxxxxxxxx"`}</Code>
          <Text c="dimmed" fz="sm">
            Ключи бывают тестовые (<Code>sk_test_…</Code>) и боевые (<Code>sk_live_…</Code>).
            Не публикуйте ключи в клиентском коде.
          </Text>
        </Section>

        <Section title="Загрузка контента">
          <Text c="dimmed" lh={1.7}>
            Файлы кладутся в S3-совместимое объектное хранилище. Совместимо с любым S3-SDK
            и <Code>aws-cli</Code>:
          </Text>
          <Code block>{`aws --endpoint-url https://s3.${brand.domain} \\
  s3 cp ./video.mp4 s3://my-bucket/video.mp4`}</Code>
        </Section>

        <Section title="Live-стриминг">
          <Text c="dimmed" lh={1.7}>
            Прямой эфир принимается по RTMP или SRT, раздаётся в HLS/LL-DASH. Строку
            публикации возьмите в карточке потока:
          </Text>
          <Code block>{`# OBS / ffmpeg → RTMP push
rtmp://ingest.${brand.domain}/live/{stream_key}

# playback
https://cdn.${brand.domain}/live/{stream_key}/index.m3u8`}</Code>
        </Section>

        <Section title="Инвалидация кэша">
          <Text c="dimmed" lh={1.7}>
            Сброс кэша по префиксу — изменения на edge применяются за 5–15 секунд:
          </Text>
          <Code block>{`curl -X POST https://api.${brand.domain}/v1/purge \\
  -H "Authorization: Bearer sk_live_..." \\
  -d '{"paths": ["/video/*", "/img/logo.png"]}'`}</Code>
        </Section>

        <Section title="SDK и библиотеки">
          <List spacing="xs" c="dimmed" fz="sm">
            <List.Item>Go — <Code>go get {brand.domain}/sdk-go</Code></List.Item>
            <List.Item>Python — <Code>pip install streamora</Code></List.Item>
            <List.Item>Node.js — <Code>npm i @streamora/sdk</Code></List.Item>
            <List.Item>PHP — <Code>composer require streamora/sdk</Code></List.Item>
          </List>
        </Section>

        <Card withBorder radius="md" padding="lg" style={{ background: 'rgba(34,211,238,0.05)' }}>
          <Text fw={600} mb={4}>
            Нужна помощь с интеграцией?
          </Text>
          <Text c="dimmed" fz="sm">
            Инженеры поддержки помогут с настройкой:{' '}
            <Anchor href={`mailto:${brand.emailSupport}`}>{brand.emailSupport}</Anchor>
          </Text>
        </Card>
      </Stack>
    </PageShell>
  )
}
