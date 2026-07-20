import type { ReactNode } from 'react'
import { Anchor, Box, Container, Group, Stack, Text, Title } from '@mantine/core'
import { Link } from 'react-router-dom'
import { IconChevronRight } from '@tabler/icons-react'

// Consistent top spacing (clears the fixed navbar) + width for all sub-pages.
export function PageShell({ size = 'md', children }: { size?: string; children: ReactNode }) {
  return (
    <Box pt={{ base: 100, sm: 132 }} pb={90}>
      <Container size={size}>{children}</Container>
    </Box>
  )
}

export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <Stack gap="sm" mb={44}>
      <Group gap={6} c="dimmed" fz="sm">
        <Anchor component={Link} to="/" c="dimmed" underline="never">
          Главная
        </Anchor>
        <IconChevronRight size={13} />
        <Text span c="brand.4">
          {title}
        </Text>
      </Group>
      <Title order={1} fz={{ base: 30, sm: 44 }} style={{ letterSpacing: '-0.02em' }}>
        {title}
      </Title>
      {subtitle && (
        <Text c="dimmed" fz="lg" maw={660}>
          {subtitle}
        </Text>
      )}
    </Stack>
  )
}
