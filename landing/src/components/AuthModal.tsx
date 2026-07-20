import { useState } from 'react'
import { Button, Group, Modal, Stack, Text, TextInput, Textarea, ThemeIcon } from '@mantine/core'
import { IconCheck } from '@tabler/icons-react'
import Logo from './Logo'
import { brand } from '../brand'

// B2B "request access" — no open signup, so no working auth is needed.
// Submitting just shows a success state (static cover; no backend on the node).
export default function AccessModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const [sent, setSent] = useState(false)

  const handleClose = () => {
    onClose()
    setTimeout(() => setSent(false), 200)
  }

  return (
    <Modal
      opened={opened}
      onClose={handleClose}
      centered
      radius="lg"
      size="md"
      overlayProps={{ backgroundOpacity: 0.65, blur: 6 }}
      title={<Logo size="sm" />}
    >
      {sent ? (
        <Stack align="center" ta="center" gap="sm" py="lg">
          <ThemeIcon size={52} radius="xl" variant="light" color="teal">
            <IconCheck size={28} stroke={2.2} />
          </ThemeIcon>
          <Text fw={700} fz="lg">
            Заявка отправлена
          </Text>
          <Text c="dimmed" fz="sm" maw={360}>
            Менеджер свяжется с вами в течение рабочего дня и откроет доступ к личному
            кабинету {brand.name}. Обычно это занимает пару часов.
          </Text>
          <Button mt="sm" radius="md" variant="default" onClick={handleClose}>
            Закрыть
          </Button>
        </Stack>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            setSent(true)
          }}
        >
          <Stack gap="md">
            <Text c="dimmed" fz="sm">
              Оставьте контакты — подключим тестовый период на 14 дней и поможем с интеграцией.
            </Text>
            <Group grow>
              <TextInput label="Имя" placeholder="Иван Петров" required radius="md" />
              <TextInput label="Компания" placeholder="ООО «Медиа»" required radius="md" />
            </Group>
            <TextInput label="Рабочая почта" type="email" placeholder="you@company.ru" required radius="md" />
            <TextInput label="Телефон" placeholder="+7 (___) ___-__-__" radius="md" />
            <Textarea label="Задача" placeholder="Кратко о проекте: стриминг, VOD, объём трафика…" minRows={2} radius="md" />
            <Button type="submit" size="md" radius="md" mt={4}>
              Отправить заявку
            </Button>
            <Text c="dimmed" fz="xs" ta="center">
              Нажимая кнопку, вы соглашаетесь с обработкой персональных данных.
            </Text>
          </Stack>
        </form>
      )}
    </Modal>
  )
}
