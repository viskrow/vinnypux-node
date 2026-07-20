import { Box, Container, SimpleGrid, Stack, Text } from '@mantine/core'
import { stats } from '../brand'

export default function Stats() {
  return (
    <Box component="section" pb={{ base: 70, sm: 100 }}>
      <Container size="lg">
        <SimpleGrid
          cols={{ base: 2, sm: 4 }}
          spacing={0}
          style={{
            borderRadius: 20,
            overflow: 'hidden',
            border: '1px solid var(--mantine-color-dark-4)',
          }}
        >
          {stats.map((s) => (
            <Stack
              key={s.label}
              gap={6}
              align="center"
              ta="center"
              py={36}
              px={20}
              style={{
                background: 'rgba(255,255,255,0.02)',
                borderInline: '0.5px solid var(--mantine-color-dark-4)',
              }}
            >
              <Text fz={{ base: 30, sm: 38 }} fw={800} className="grad-text" lh={1}>
                {s.value}
              </Text>
              <Text c="dimmed" fz="sm">
                {s.label}
              </Text>
            </Stack>
          ))}
        </SimpleGrid>
      </Container>
    </Box>
  )
}
