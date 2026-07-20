import { Badge, Box, Button, Container, Group, Stack, Text, Title } from '@mantine/core'
import { IconArrowRight } from '@tabler/icons-react'
import { Link } from 'react-router-dom'
import { brand } from '../brand'
import { useAccess } from '../access'

export default function Hero() {
  const openAccess = useAccess()
  return (
    <Box
      component="section"
      pt={{ base: 120, sm: 160 }}
      pb={{ base: 60, sm: 90 }}
      style={{ minHeight: '100vh', display: 'flex', alignItems: 'center' }}
    >
      <Container size="lg" w="100%">
        <Stack align="center" gap="xl" ta="center">
          <Badge
            size="lg"
            radius="xl"
            variant="light"
            color="brand"
            leftSection={<Box w={7} h={7} bg="brand.4" style={{ borderRadius: '50%' }} />}
          >
            Новая точка присутствия: Новосибирск
          </Badge>

          <Title order={1} fz={{ base: 42, sm: 68 }} maw={880} lh={1.06} style={{ letterSpacing: '-0.03em' }}>
            {brand.tagline.split(' ').slice(0, 2).join(' ')}{' '}
            <Text span inherit className="grad-text">
              {brand.tagline.split(' ').slice(2).join(' ')}
            </Text>
          </Title>

          <Text c="dimmed" fz={{ base: 'md', sm: 'xl' }} maw={620} lh={1.65}>
            {brand.lead}
          </Text>

          <Group gap="sm" justify="center" mt="sm">
            <Button size="lg" radius="md" onClick={openAccess}>
              Запросить доступ
            </Button>
            <Button
              size="lg"
              radius="md"
              variant="default"
              component={Link}
              to="/docs"
              rightSection={<IconArrowRight size={18} />}
            >
              Документация
            </Button>
          </Group>

          <Text c="dimmed" fz="sm" mt="xs">
            Тестовый период 14 дней · без карты · подключение за час
          </Text>
        </Stack>
      </Container>
    </Box>
  )
}
