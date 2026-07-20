import { Box, Group, Text } from '@mantine/core'
import { brand } from '../brand'

export default function Logo({ size = 'md' }: { size?: 'sm' | 'md' }) {
  const px = size === 'sm' ? 26 : 32
  return (
    <Group gap={10} wrap="nowrap">
      <Box
        w={px}
        h={px}
        style={{
          borderRadius: 8,
          background: 'linear-gradient(135deg, var(--mantine-color-brand-5), #3b82f6)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: '0 0 16px rgba(34, 211, 238, 0.4)',
          flexShrink: 0,
        }}
      >
        <svg width={px * 0.58} height={px * 0.58} viewBox="0 0 24 24" fill="none"
             stroke="white" strokeWidth="2.3" strokeLinecap="round">
          <path d="M8 12a4 4 0 0 1 4-4" />
          <path d="M5 12a7 7 0 0 1 7-7" />
          <circle cx="12" cy="12" r="1.9" fill="white" stroke="none" />
        </svg>
      </Box>
      <Text fw={700} fz={size === 'sm' ? 'md' : 'lg'} style={{ letterSpacing: '-0.02em' }}>
        {brand.name}
      </Text>
    </Group>
  )
}
