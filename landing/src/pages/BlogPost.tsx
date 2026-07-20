import { Anchor, Group, Stack, Text, Title } from '@mantine/core'
import { IconArrowLeft } from '@tabler/icons-react'
import { Link, useParams } from 'react-router-dom'
import { PageShell } from '../components/Page'
import { posts } from '../content/posts'
import NotFound from './NotFound'

function formatDate(iso: string) {
  const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']
  const [y, m, d] = iso.split('-').map(Number)
  return `${d} ${months[m - 1]} ${y}`
}

export default function BlogPost() {
  const { slug } = useParams()
  const post = posts.find((p) => p.slug === slug)
  if (!post) return <NotFound />

  return (
    <PageShell size="sm">
      <Stack gap="lg">
        <Anchor component={Link} to="/blog" c="dimmed" fz="sm">
          <Group gap={4} wrap="nowrap">
            <IconArrowLeft size={15} />
            <Text span>Все статьи</Text>
          </Group>
        </Anchor>

        <Stack gap="xs">
          <Group gap="xs" c="dimmed" fz="xs">
            <Text span>{formatDate(post.date)}</Text>
            <Text span>·</Text>
            <Text span>{post.readMins} мин чтения</Text>
          </Group>
          <Title order={1} fz={{ base: 28, sm: 40 }} style={{ letterSpacing: '-0.02em' }}>
            {post.title}
          </Title>
        </Stack>

        <Stack gap="md">
          {post.body.map((para, i) => (
            <Text key={i} c="dimmed" fz="lg" lh={1.8}>
              {para}
            </Text>
          ))}
        </Stack>
      </Stack>
    </PageShell>
  )
}
