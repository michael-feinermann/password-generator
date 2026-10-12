# Public design preview

This development harness reuses `MainWindow.cs` and the production control theme with a separate fake `AppModel`. It never creates a native window, initializes the entropy pool, loads signing material, calls runtime verification, or writes the clipboard. Displayed values are explicitly public design fixtures and must never be used as passwords or wallet seeds.

Render one full page from the repository root:

```powershell
& "$env:ProgramFiles\dotnet\dotnet.exe" run --project Windows/PasswordGenerator.DesignPreview -- --language de --mode Bip39 --width 1060 --height 840 --phase Ready --full true --output Windows/artifacts/design-preview.png
```

`--phase Collecting|Ready|Generated`, `--visible true|false`, and `--length N` select fixtures. Without `--full true`, the PNG shows the viewport at the requested dimensions. The render reuses the private production `ApplyLayout` method via reflection and does not require weakening the app's capture protection. Both the presentation source and the production window's native-handle field are checked to confirm that no native window was created.

`--check-controls true` invokes the real view's button handlers with the fake model: BIP39 length changes, replacement of the active entropy legend, mode selection, PIN slider keyboard commands, and Hex case selection without changing length or generation state. Slider track bindings and page-step commands are also checked. Reveal and discard confirmation dialogs, native caption buttons, real security guards, and real secret lifetimes are outside this harness.

```powershell
& Windows/PasswordGenerator.DesignPreview/Render-Matrix.ps1
```

The matrix covers five modes, two languages, three window sizes, and collecting, ready, concealed, and revealed states (120 scenes), including control checks. Run it directly with `--matrix Windows/artifacts/design-review` after building. Each PNG has a matching JSON geometry report. Checks examine non-trimmed text, mixed Run font sizes and typefaces, string button labels, and horizontal viewport bounds for clipping. Manual image review remains necessary for visual quality, focus styling, and operating-system title bar behavior. All generated files are kept beneath ignored `Windows/artifacts/`.
