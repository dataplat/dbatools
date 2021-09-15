# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.DoDotSource' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
            $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
        }
        if ($args[0]) {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name DoDotSource -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
        } else {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name DoDotSource -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.DoDotSource'" -ErrorRecord $_ -Target 'Import.DoDotSource'
    }
} -Description "Causes the module to be imported using dotsourcing. Security policy may require it, also useful for debugging. This configuration setting persists across all PowerShell consoles for this user."

# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.StrictSecurityMode' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
            $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
        }
        if ($args[0]) {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name StrictSecurityMode -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
        } else {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name StrictSecurityMode -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.StrictSecurityMode'" -ErrorRecord $_ -Target 'Import.StrictSecurityMode'
    }
} -Description "Causes the module to import its components only from the module directory. This makes it harder to update the module, but may be required by security policy. This configuration setting persists across all PowerShell consoles for this user."

# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.AlwaysBuildLibrary' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
            $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
        }
        if ($args[0]) {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name AlwaysBuildLibrary -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
        } else {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name AlwaysBuildLibrary -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.AlwaysBuildLibrary'" -ErrorRecord $_ -Target 'Import.AlwaysBuildLibrary'
    }
} -Description "Causes the module to compile the library from source on every import. Of interest for developers only, as this imposes a significant increase in import time. This configuration setting persists across all PowerShell consoles for this user."

# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.SerialImport' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
            $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
        }
        if ($args[0]) {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name SerialImport -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
        } else {
            $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name SerialImport -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.SerialImport'" -ErrorRecord $_ -Target 'Import.SerialImport'
    }
} -Description "Enabling this will cause the module to perform import in a serial manner, not parallelizing anything. This will impose a significant delay on import, but reduces the CPU impact during import. Setting this for an unattended script may be useful to avoid resource alerts. Can be set on script level by placing the following code in the first line: '`$dbatools_serialimport = `$true'. This configuration setting persists across all PowerShell consoles for this user."

# Check for SqlPs
Set-DbatoolsConfig -Name 'Import.SqlpsCheck' -Value $true -Initialize -Validation bool -Description "Does not warn about sqlps being imported at the time of the dbatools import"