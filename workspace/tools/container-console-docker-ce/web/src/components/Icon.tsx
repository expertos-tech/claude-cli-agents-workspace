const PATHS = {
  alert: 'M12 3 2.5 20h19L12 3Zm0 6.5v5m0 3v.01',
  arrowLeft: 'M19 12H5m6-6-6 6 6 6',
  check: 'm5 12.5 4.5 4.5L19 7.5',
  chevronDown: 'm6 9 6 6 6-6',
  chevronUp: 'm6 15 6-6 6 6',
  close: 'M6 6l12 12M18 6 6 18',
  compose: 'M4 5h7v6H4zm9 0h7v6h-7zM8.5 13h7v6h-7z',
  container: 'M3 8.5 12 4l9 4.5v7L12 20l-9-4.5v-7Zm0 0 9 4.5m9-4.5L12 13m0 0v7',
  download: 'M12 4v11m-5-5 5 5 5-5M5 20h14',
  environment: 'M4 5h16v6H4zm0 8h16v6H4zm3-5h.01M7 16h.01',
  file: 'M6 3h8l4 4v14H6V3Zm8 0v4h4',
  home: 'M4 11 12 4l8 7v9h-5v-6H9v6H4v-9Z',
  hourglass: 'M7 3h10M7 21h10M8 3v4l4 5 4-5V3M8 21v-4l4-5 4 5v4',
  image: 'M12 3 3 8l9 5 9-5-9-5Zm-9 9 9 5 9-5M3 16l9 5 9-5',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Zm0-10v5m0-8v.01',
  kubernetes:
    'M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3Zm0 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm0-5v5m0 8v5M4 7.5l4.5 2.5m7 4 4.5 2.5M20 7.5 15.5 10m-7 4L4 16.5',
  logs: 'M5 4h14v16H5V4Zm3 4h8m-8 4h8m-8 4h5',
  menu: 'M4 7h16M4 12h16M4 17h16',
  minus: 'M5 12h14',
  network: 'M12 4v6m0 0H5v5m7-5h7v5M12 10v5M3 15h4v5H3zm7 0h4v5h-4zm7 0h4v5h-4zM10 3h4v4h-4z',
  play: 'M7 4.5v15L19.5 12 7 4.5Z',
  plus: 'M12 5v14M5 12h14',
  restart: 'M4 12a8 8 0 1 0 2.5-5.8L4 8.5M4 4v4.5h4.5',
  scale: 'M4 9V4h5M20 15v5h-5M4 4l6.5 6.5M20 20l-6.5-6.5',
  stop: 'M6 6h12v12H6z',
  terminal: 'M3 5h18v14H3V5Zm4 4 3.5 3L7 15m6 0h4',
  trash: 'M4 7h16M9 7V4h6v3m3 0-1 13H7L6 7m4 4v5m4-5v5',
  volume:
    'M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3Zm0 0v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3',
} as const

export type IconName = keyof typeof PATHS

interface IconProps {
  name: IconName
  size?: number
}

/** Draws a line icon. It is always decorative: the text beside it, or the control's name, says it. */
export function Icon({ name, size = 16 }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={PATHS[name]} />
    </svg>
  )
}
