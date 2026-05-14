# SAR ADC Project Rules

## Important

- **Backup Chinese comments before translating to English** - Keep original Chinese version in `backup_chinese/` folder
- All code comments must be in **English** to prevent Vivado garbled characters

## Code Style

- Use `logic` instead of `reg`
- Use explicit bit widths for all signals
- Use `parameter int` for integer parameters
- Naming: `clk`, `rst_n`, `d_` (data), `q_` (registered output)

## File Organization

| Type | Location |
|------|----------|
| Sources | `sources_1/new/` |
| Testbenches | `sim_1/new/` |
| Constraints | `constrs_1/new/` |
| Chinese Backup | `backup_chinese/` |

## Git Commits

Use conventional format: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
