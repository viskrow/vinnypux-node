import { createTheme, type MantineColorsTuple } from '@mantine/core'

// Media-tech cyan/teal — distinct from generic Mantine blue.
const brandColor: MantineColorsTuple = [
  '#e2fbff', '#c9f2f9', '#98e4f1', '#63d6e9', '#3ccae2',
  '#23c3de', '#08bfdd', '#00a8c4', '#0095af', '#00808c',
]

export const theme = createTheme({
  primaryColor: 'brand',
  primaryShade: { light: 6, dark: 5 },
  colors: { brand: brandColor },
  defaultRadius: 'md',
  fontFamily:
    '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", system-ui, sans-serif',
  headings: {
    fontWeight: '800',
    sizes: {
      h1: { fontWeight: '800', lineHeight: '1.1' },
      h2: { fontWeight: '800', lineHeight: '1.15' },
    },
  },
})
