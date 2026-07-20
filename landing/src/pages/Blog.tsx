import { Card, Group, Stack, Text, Title } from '@mantine/core'
import { Link } from 'react-router-dom'
import { PageHeader, PageShell } from '../components/Page'
import { posts } from '../content/posts'

function formatDate(iso: string) {
  const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']
  const [y, m, d] = iso.split('-').map(Number)
  return `${d} ${months[m - 1]} ${y}`
}

export default function Blog() {
  return (
    <PageShell size="md">
      <PageHeader title="Блог" subtitle="Инженерные заметки о доставке медиа, стриминге и работе сети." />

      <Stack gap="md">
        {posts.map((p) => (
          <Card
            key={p.slug}
            component={Link}
            to={`/blog/${p.slug}`}
            withBorder
            radius="md"
            padding="lg"
            style={{ background: 'rgba(255,255,255,0.02)' }}
          >
            <Stack gap={8}>
              <Group gap="xs" c="dimmed" fz="xs">
                <Text span>{formatDate(p.date)}</Text>
                <Text span>·</Text>
                <Text span>{p.readMins} мин чтения</Text>
              </Group>
              <Title order={3} fz={{ base: 18, sm: 22 }}>
                {p.title}
              </Title>
              <Text c="dimmed" fz="sm" lh={1.6}>
                {p.excerpt}
              </Text>
            </Stack>
          </Card>
        ))}
      </Stack>
    </PageShell>
  )
}
