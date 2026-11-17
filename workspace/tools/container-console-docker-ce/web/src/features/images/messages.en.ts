export const messages = {
  nav: 'Images',
  title: 'Images',
  description: 'The progress lines of a pull show in the actions panel, below the screen.',
  pullTitle: 'Pull image',
  referenceLabel: 'Image reference',
  referenceHint: 'Example: alpine:3.20',
  referenceInvalid:
    'The reference must start with a letter or digit and contain only letters, digits and the signs . _ : / @ -, up to 512 characters.',
  pull: 'Pull',
  caption: { one: '{count} image', other: '{count} images' },
  empty: 'No image exists right now.',
  columnReference: 'Reference',
  columnId: 'Id',
  columnSize: 'Size',
  columnCreated: 'Created',
  remove: 'Remove',
  removeAria: 'Remove image {reference}',
  removeTitle: 'Remove image {reference}?',
  removeBody:
    'The removal does not use force: if the image is in use, it stays here and the Docker error shows in the actions panel.',
} as const
