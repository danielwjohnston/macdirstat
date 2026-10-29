# MacDirStat

A native, high-performance macOS port of the classic **WinDirStat** disk usage analyzer, engineered with 1-for-1 feature and aesthetic parity, native AppKit architecture, and a hardware-accelerated **Metal 3** cushion-shading rendering pipeline.

![MacDirStat Screenshot](https://raw.githubusercontent.com/danielwjohnston/macdirstat/main/screenshot.png)

---

## Highlights & Features

- **1-for-1 WinDirStat Parity**:
  - **Synchronized 3-Pane Dashboard**: File Hierarchy Tree (`NSOutlineView`), Extension Statistics (`NSTableView`), and Cushion Treemap.
  - **Exact Van Wijk Cushion Shading**: Direct mathematical port of `TreeMap.cpp` / `AddRidge()` parabolic surface accumulation $\Delta z$ and normalized directional diffuse lighting.
  - **In-Tree Subtree % Bar Gauges**: 3D beveled horizontal bar gauges inside table columns.
  - **`<Free Space>` and `<Unknown Space>` Pseudo-Nodes**: Accurate disk volume overhead representation queried via `statvfs`.
  - **"Select Drives..." Modal Dialog**: Choose All Local Drives, individual drive checklists with capacity meters, or a custom folder.
  - **Custom User Cleanups**: Execute custom shell commands with `%p` (path), `%n` (name), and `%s` (formatted size) macro parameters.
  - **CSV Report Export**: Export disk usage or extension statistics to `.csv` format (`File > Export to CSV...`).

- **Hardware-Accelerated Metal 3 Pipeline**:
  - Offloads per-pixel cushion illumination directly to GPU fragment shaders (`MTKView`).
  - Single-pass instanced quad rendering capable of rendering 100,000+ files smoothly at Retina resolutions.
  - Crisp $0.5\text{px}$ hairline tile boundaries and anti-aliased selection outlines.

- **Multi-Theme Engine with Dynamic Light & Dark Mode**:
  - **Faithful WinDirStat (Classic)**: Authentic Win32 system colors and sunken bevels.
  - **Dracula**: Iconic dark palette (`#282a36`) with vibrant treemap accents.
  - **Alucard**: High-contrast obsidian and crimson variant.
  - **Nord**: Arctic frost palette (`#2e3440` polar night, `#eceff4` snow storm).
  - **macOS System**: Adapts seamlessly to macOS Light / Dark Aqua appearance.

- **Modern macOS Enhancements**:
  - **APFS Clone Deduplication**: Deduplicates hard links and APFS copy-on-write file clones via POSIX inode tracking (`stat.st_dev` / `stat.st_ino`).
  - **Native Quick Look**: Press `Spacebar` to immediately preview any selected file.
  - **Live Package Toggling**: Inspect inside `.app` / `.framework` bundles or treat them as atomic files.

---

## Requirements

- macOS 13.0 (Ventura) or newer (Apple Silicon and Intel x86_64 supported)
- Metal 3 capable GPU (Apple Silicon or Intel UHD / AMD Radeon)

---

## Build & Installation

### Build with Swift Package Manager:
```bash
git clone https://github.com/danielwjohnston/macdirstat.git
cd macdirstat
./build_app.sh
```
This compiles the release binary with Swift 6 strict concurrency checks, packages it into `/Applications/MacDirStat.app`, sets the high-resolution macOS squircle icon, and ad-hoc signs the application bundle.

### Run Unit Tests:
```bash
swift test
```

---

## License

GPL-3.0 (matching WinDirStat open-source licensing)
