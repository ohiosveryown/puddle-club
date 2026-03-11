# Vue files

- The order of every .vue file should be template, style, script

# CSS

- Try to limit nesting CSS as much as possible so styling can be easier to read and more durable.
- Prefer using flexbox over css grid when possible. Use the grid mixins from style/grid.scss
- Properties should follow a specific order, from broad layout impact to finer details (with some caveats [see list below]) i.e – layout, box model, visual, typography, misc.
  - display
  - position
  - z-index
  - margin
  - padding
  - width
  - height
  - border
  - color
  - background
  - box-shadow
  - font-size
  - font-family
  - text-align
  - text-transform
  - transform
  - transition
  - overflow
  - cursor
  - etc
