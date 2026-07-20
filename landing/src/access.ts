import { createContext, useContext } from 'react'

// Opens the "Запросить доступ" modal — provided by Layout, consumed anywhere.
export const AccessContext = createContext<() => void>(() => {})
export const useAccess = () => useContext(AccessContext)
