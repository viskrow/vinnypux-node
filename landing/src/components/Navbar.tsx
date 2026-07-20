import { Anchor, Box, Burger, Button, Container, Drawer, Group, Stack } from '@mantine/core'
import { useDisclosure, useWindowScroll } from '@mantine/hooks'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import { useAccess } from '../access'

// Section links point at "/#…" so they work from any page (jump home + scroll);
// "Документация" is a real route.
const sectionLinks = [
  { label: 'Возможности', href: '/#features' },
  { label: 'Тарифы', href: '/#pricing' },
  { label: 'Статус сети', href: '/#status' },
]

export default function Navbar() {
  const [scroll] = useWindowScroll()
  const scrolled = scroll.y > 40
  const openAccess = useAccess()
  const [drawer, { toggle: toggleDrawer, close: closeDrawer }] = useDisclosure(false)

  return (
    <>
      <Box
        component="nav"
        pos="fixed"
        top={0}
        left={0}
        right={0}
        py={12}
        style={{
          zIndex: 100,
          transition: 'background 0.3s ease, border-color 0.3s ease',
          background: scrolled ? 'rgba(5, 7, 13, 0.72)' : 'transparent',
          backdropFilter: scrolled ? 'blur(20px) saturate(160%)' : 'none',
          WebkitBackdropFilter: scrolled ? 'blur(20px) saturate(160%)' : 'none',
          borderBottom: scrolled ? '1px solid var(--mantine-color-dark-4)' : '1px solid transparent',
        }}
      >
        <Container size="lg">
          <Group justify="space-between" wrap="nowrap">
            <Anchor component={Link} to="/" underline="never" c="gray.0">
              <Logo />
            </Anchor>

            <Group gap={4} visibleFrom="sm">
              {sectionLinks.map((l) => (
                <Anchor key={l.href} href={l.href} underline="never" c="dimmed" fz="sm" px={12} py={6} style={{ borderRadius: 8 }}>
                  {l.label}
                </Anchor>
              ))}
              <Anchor component={Link} to="/docs" underline="never" c="dimmed" fz="sm" px={12} py={6} style={{ borderRadius: 8 }}>
                Документация
              </Anchor>
            </Group>

            <Button size="sm" radius="md" onClick={openAccess} visibleFrom="sm">
              Запросить доступ
            </Button>

            <Burger opened={drawer} onClick={toggleDrawer} hiddenFrom="sm" size="sm" aria-label="Меню" />
          </Group>
        </Container>
      </Box>

      <Drawer
        opened={drawer}
        onClose={closeDrawer}
        position="right"
        size="78%"
        title={<Logo size="sm" />}
        overlayProps={{ backgroundOpacity: 0.55, blur: 4 }}
      >
        <Stack gap={4} mt="md">
          {sectionLinks.map((l) => (
            <Anchor key={l.href} href={l.href} onClick={closeDrawer} underline="never" c="gray.2" py={10} fz="lg">
              {l.label}
            </Anchor>
          ))}
          <Anchor component={Link} to="/docs" onClick={closeDrawer} underline="never" c="gray.2" py={10} fz="lg">
            Документация
          </Anchor>
          <Button
            mt="lg"
            size="md"
            radius="md"
            onClick={() => {
              closeDrawer()
              openAccess()
            }}
          >
            Запросить доступ
          </Button>
        </Stack>
      </Drawer>
    </>
  )
}
