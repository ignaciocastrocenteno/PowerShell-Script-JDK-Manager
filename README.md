# Switch-Java (PowerShell)

## Introduction
A simple, robust, and maintainable PowerShell utility to **switch between multiple installed Java JDK versions on Windows**. It updates `JAVA_HOME` and ensures your `PATH` points to `%JAVA_HOME%\bin`, avoiding conflicts between JDK installations. Designed for developers working across projects that require different Java versions (e.g., 8, 11, 17, 21, 25).

> Default JDK locations in this repository follow my own setup:
>
> `D:\Ignacio\Aplicaciones\Java JDKs\<VERSION_NAME>`
>
> Example: `D:\Ignacio\Aplicaciones\Java JDKs\Java 21`

## Features
- Switch Java version with one command (`-Version 8|11|17|21|25`).
- Write to **User** or **Machine** scope (`-Scope User|Machine`).
- Idempotent PATH management: ensures only **one** `%JAVA_HOME%\bin` entry and **cleans conflicting** JDK bin paths.
- Validation of target JDK (checks `bin\java.exe` and `bin\javac.exe`).
- **Interactive mode** for quick selection.
- **Dry run** mode to preview changes without applying them.
- Optional external config file `jdk-versions.json` for easy maintenance.
- Clear, informative output with robust error handling.

## How it works
1. **Configuration:**
   - The script ships with a built-in map of JDK versions → installation directories:
     - `8`  → `D:\Ignacio\Aplicaciones\Java JDKs\Java 8`
     - `11` → `D:\Ignacio\Aplicaciones\Java JDKs\Java 11`
     - `17` → `D:\Ignacio\Aplicaciones\Java JDKs\Java 17`
     - `21` → `D:\Ignacio\Aplicaciones\Java JDKs\Java 21`
     - `25` → `D:\Ignacio\Aplicaciones\Java JDKs\Java 25`
   - If a `jdk-versions.json` file exists next to the script, it will **override** these paths.

2. **Switching:**
   - When you run `-Version <number>`, the script resolves aliases (e.g., `Java 17`, `jdk-21`) to the major version (e.g., `17`, `21`).
   - It validates the target path by checking for `bin\java.exe` and `bin\javac.exe`.
   - It sets `JAVA_HOME` at the selected scope and updates `PATH` so that `%JAVA_HOME%\bin` is at the beginning.
   - It **removes direct JDK bin paths** from PATH to prevent conflicts.
   - It broadcasts an **environment change event** (`WM_SETTINGCHANGE`) so GUI apps can pick up the new variables (some may still require reopening).

3. **Current session update:**
   - The script also updates `JAVA_HOME` and `PATH` for the **current PowerShell session**, allowing you to use the new version immediately without opening a new terminal. The `-Current` flag will display both `java --version` and `javac --version` outputs.

## How to execute the script
1. **Clone or download** the repository.
2. Open **PowerShell**.
3. Navigate to the script folder and run one of the following:

```powershell
# Switch to JDK 21 at Machine scope (requires Admin)
PS> .\Switch-Java.ps1 -Version 21 -Scope Machine

# Switch to JDK 8 at User scope
PS> .\Switch-Java.ps1 -Version 8

# Interactive menu
PS> .\Switch-Java.ps1 -Interactive

# Show current JAVA_HOME and java/javac versions
PS> .\Switch-Java.ps1 -Current

# Preview changes without applying (now supports 17 too)
PS> .\Switch-Java.ps1 -Version 17 -DryRun
```

> **Execution policy note:** If you haven't enabled script execution, run:
>
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

## Good Practices Implemented
- **Scoped writes**: Choose User or Machine scope with explicit admin checks.
- **Idempotent PATH updates**: No duplicates; `%JAVA_HOME%\bin` is guaranteed to be present once.
- **Conflict cleanup**: Removes direct JDK bin paths that can shadow `%JAVA_HOME%\bin`.
- **Validation before switching**: Ensures `java.exe` and `javac.exe` exist.
- **Clear error messages** and **dry-run mode** for safe changes.
- **Interactive UX** and **helpful usage banner**.
- **Optional JSON config** for easy maintenance without editing the script.
- **Environment change broadcast** so desktop apps can pick up updates.

## Notes & Limitations
- **Admin rights** are required to modify **Machine** scope environment variables.
- Some applications or terminals may need to be **restarted** to pick up changes.
- PATH cleanup is conservative. If you have custom JDK paths that should remain, consider using the optional `jdk-versions.json` and ensure your other PATH entries are not mistakenly matching the cleanup patterns.
- The script targets **Windows** (PowerShell on Windows). It isn't intended for WSL or Linux/macOS.
- JDK **install directory names must match** your actual setup. Adjust either the built-in map or create `jdk-versions.json` to reflect exact paths.

## License
This project is licensed under the GNU General Public License v3.0 (GPL-3.0).

By using, modifying, or distributing this software, you agree to the terms defined in the GPL-3.0 license. In summary:

You are free to run, study, modify, and share the software.

If you distribute modified versions of the program, the result must also be licensed under GPL-3.0, ensuring the same freedoms for users.

Any redistributed version—modified or unmodified—must include a copy of the license and appropriate copyright notices.

No warranty is provided, as explicitly described in the license.

For the full legal text, refer to the official GPL-3.0 license:

https://www.gnu.org/licenses/gpl-3.0.en.html
