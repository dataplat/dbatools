# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.StrictSecurityMode' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not ($isLinux -or $IsMacOS)) {
            if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
                $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
            }
            if ($args[0]) {
                $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name StrictSecurityMode -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
            } else {
                $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name StrictSecurityMode -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
            }
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.StrictSecurityMode'" -ErrorRecord $_ -Target 'Import.StrictSecurityMode'
    }
} -Description "Causes the module to import its components only from the module directory. This makes it harder to update the module, but may be required by security policy. This configuration setting persists across all PowerShell consoles for this user."

# Handle dotsourcing on import
Set-DbatoolsConfig -Name 'Import.SerialImport' -Value $false -Initialize -Validation bool -Handler {
    try {
        if (-not ($isLinux -or $IsMacOS)) {
            if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System")) {
                $null = New-Item "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -ItemType Container -Force -ErrorAction Stop
            }
            if ($args[0]) {
                $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name SerialImport -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
            } else {
                $null = New-ItemProperty "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\System" -Name SerialImport -PropertyType DWORD -Value 0 -Force -ErrorAction Stop
            }
        }
        # Scope Boundary exception: $cfg is defined in Set-DbatoolsConfig
        Register-DbatoolsConfig -Config $cfg
    } catch {
        Write-Message -Level Warning -Message "Failed to apply configuration 'Import.SerialImport'" -ErrorRecord $_ -Target 'Import.SerialImport'
    }
} -Description "Enabling this will cause the module to perform import in a serial manner, not parallelizing anything. Security policy may require it, also useful for debugging. This configuration setting persists across all PowerShell consoles for this user. This will impose a significant delay on import, but reduces the CPU impact during import. Setting this for an unattended script may be useful to avoid resource alerts. Can be set on script level by placing the following code in the first line: '`$dbatools_dotsourcemodule = `$true'. This configuration setting persists across all PowerShell consoles for this user."

# Check for SqlPs
Set-DbatoolsConfig -Name 'Import.SqlpsCheck' -Value $true -Initialize -Validation bool -Description "Does not warn about sqlps being imported at the time of the dbatools import"

# Check for Encryption
Set-DbatoolsConfig -Name 'Import.EncryptionMessageCheck' -Value $true -Initialize -Validation bool -Description "Does not warn about new Microsoft encryption defaults"