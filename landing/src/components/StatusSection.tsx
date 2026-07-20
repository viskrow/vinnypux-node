import { Badge, Box, Card, Container, Group, Stack, Table, Text, Title } from '@mantine/core'

const pops = [
  { region: 'Москва (2 ЦОД)', nodes: 9, latency: '11 мс', state: 'ok' },
  { region: 'Санкт-Петербург', nodes: 6, latency: '14 мс', state: 'ok' },
  { region: 'Новосибирск', nodes: 4, latency: '22 мс', state: 'ok' },
  { region: 'Екатеринбург', nodes: 4, latency: '19 мс', state: 'ok' },
  { region: 'Казань', nodes: 3, latency: '17 мс', state: 'ok' },
  { region: 'Краснодар', nodes: 3, latency: '21 мс', state: 'degraded' },
  { region: 'Алматы', nodes: 3, latency: '28 мс', state: 'ok' },
]

function StateBadge({ state }: { state: string }) {
  if (state === 'degraded') {
    return <Badge color="yellow" variant="light" radius="sm">Плановые работы</Badge>
  }
  return <Badge color="teal" variant="light" radius="sm">Работает</Badge>
}

export default function StatusSection() {
  return (
    <Box component="section" id="status" py={{ base: 70, sm: 100 }}>
      <Container size="lg">
        <Group justify="space-between" align="flex-end" mb={40} wrap="wrap" gap="md">
          <Stack gap={14}>
            <Text tt="uppercase" fw={600} fz="xs" c="brand.4" style={{ letterSpacing: '0.12em' }}>
              Статус сети
            </Text>
            <Title order={2} fz={{ base: 28, sm: 40 }} style={{ letterSpacing: '-0.02em' }}>
              Все точки присутствия онлайн
            </Title>
          </Stack>
          <Group gap={8}>
            <Box w={9} h={9} bg="teal.5" style={{ borderRadius: '50%', boxShadow: '0 0 10px var(--mantine-color-teal-5)' }} />
            <Text c="dimmed" fz="sm">Аптайм за 90 дней — 99,98%</Text>
          </Group>
        </Group>

        <Card padding={0} radius="lg" withBorder style={{ background: 'rgba(255,255,255,0.02)', overflow: 'hidden' }}>
          <Table.ScrollContainer minWidth={520}>
            <Table verticalSpacing="md" horizontalSpacing="lg" highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Регион</Table.Th>
                  <Table.Th>Ноды</Table.Th>
                  <Table.Th>Задержка</Table.Th>
                  <Table.Th>Статус</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {pops.map((p) => (
                  <Table.Tr key={p.region}>
                    <Table.Td fw={500}>{p.region}</Table.Td>
                    <Table.Td c="dimmed">{p.nodes}</Table.Td>
                    <Table.Td c="dimmed">{p.latency}</Table.Td>
                    <Table.Td><StateBadge state={p.state} /></Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Card>
      </Container>
    </Box>
  )
}
