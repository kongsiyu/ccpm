# Quick Install

## Unix/Linux/macOS

```bash
curl -sSL https://automaze.io/ccpm | bash
```

Or with wget:

```bash
wget -qO- https://automaze.io/ccpm | bash
```

## Windows (PowerShell)

```powershell
iwr -useb https://automaze.io/ccpm | iex
```

Or download and execute:

```powershell
curl -o ccpm.bat https://automaze.io/ccpm && ccpm.bat
```

## One-liner alternatives

### Unix/Linux/macOS (direct commands)
```bash
git clone https://github.com/automazeio/ccpm.git . && rm -rf .git
```

### Windows (cmd)
```cmd
git clone https://github.com/automazeio/ccpm.git . && rmdir /s /q .git
```

### Windows (PowerShell)
```powershell
git clone https://github.com/automazeio/ccpm.git .; Remove-Item -Recurse -Force .git
```
