# GUI Design System

## Color Palette

### Brand Colors

| Name | Hex | Usage |
|------|-----|-------|
| Adventurers Orange | #FF6B35 | Primary accent, buttons, active states |
| Deep Navy | #0D1B2A | Backgrounds, dark surfaces |
| Midnight | #1B2838 | Elevated surfaces, cards |

### Semantic Colors

| Name | Light | Dark | Usage |
|------|-------|------|-------|
| Success | #34C759 | #30D158 | Gate passed, completed tasks |
| Warning | #FF9500 | #FF9F0A | Gate running, in-progress |
| Error | #FF3B30 | #FF453A | Gate failed, errors |
| Info | #007AFF | #0A84FF | Informational states |

### Gate Colors

| Gate | Color |
|------|-------|
| SyntaxGate | Blue (#007AFF) |
| RepeatGate | Purple (#AF52DE) |
| CompilationGate | Green (#34C759) |
| MemoryGate | Orange (#FF9500) |
| ObjectiveGate | Red (#FF3B30) |

### Risk Level Colors

| Level | Color |
|-------|-------|
| readOnly | Blue |
| network | Yellow |
| write | Orange |
| execute | Red |
| destructive | Crimson |

## Typography

| Style | Font | Size | Weight |
|-------|------|------|--------|
| Title | SF Pro | 28pt | Bold |
| Heading | SF Pro | 20pt | Semibold |
| Subhead | SF Pro | 15pt | Medium |
| Body | SF Pro | 13pt | Regular |
| Caption | SF Pro | 11pt | Regular |
| Code | SF Mono | 12pt | Regular |

## Spacing

| Token | Value |
|-------|-------|
| xs | 4pt |
| sm | 8pt |
| md | 12pt |
| lg | 16pt |
| xl | 24pt |
| xxl | 32pt |

## Corner Radius

| Token | Value |
|-------|-------|
| sm | 6pt |
| md | 10pt |
| lg | 14pt |
| xl | 20pt |
| pill | 999pt |

## Shadows

| Token | Usage |
|-------|-------|
| lift | Subtle elevation for cards |
| elevation | Floating elements |
| glow(color:) | Active/focused elements |

## Layout

### Three-Panel NavigationSplitView

```
Sidebar (200-300pt) → Content (flexible) → Inspector (250-350pt)
```

### Thread List (Sidebar)

- Row height: 48pt
- Status indicator: 8pt circle
- Avatar: 32pt circle
- Search bar: 32pt height

### Message List (Content)

- Message spacing: 8pt
- Code block padding: 12pt
- Timestamp: caption size, tertiary color

### Gate Progress (Content)

- Node size: 40pt circle
- Connector width: 2pt
- Spacing between nodes: 24pt
