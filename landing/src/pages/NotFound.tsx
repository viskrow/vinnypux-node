import { Button, Stack, Text, Title } from '@mantine/core'
import { Link } from 'react-router-dom'
import { PageShell } from '../components/Page'

export default function NotFound() {
  return (
    <PageShell size="sm">
      <Stack align="center" ta="center" gap="md" py={60}>
        <Title fz={{ base: 64, sm: 96 }} className="grad-text" lh={1}>
          404
        </Title>
        <Text c="dimmed" fz="lg" maw={420}>
          Страница не найдена. Возможно, она была перемещена или удалена.
        </Text>
        <Button component={Link} to="/" radius="md" mt="sm">
          На главную
        </Button>
      </Stack>
    </PageShell>
  )
}
