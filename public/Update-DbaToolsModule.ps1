function Update-DbaToolsModule {
    <#
    .SYNOPSIS
        Deploys or updates the dbatools PowerShell module to remote servers

    .DESCRIPTION
        Automates deployment of dbatools module to one or more remote servers, particularly useful for
        air-gapped or non-internet-connected environments. This function copies the dbatools module
        from a source location to remote servers' PowerShell module directories.

        Perfect for maintaining consistent dbatools versions across your SQL Server estate without
        requiring each server to have internet access or PowerShell Gallery connectivity.

        Supports two deployment methods:
        1. PSRemoting (default) - Full featured with remote verification and proper error handling
        2. Admin Share - Simple file copy when PSRemoting is not available

    .PARAMETER ComputerName
        Target computer(s) where dbatools will be deployed or updated.
        Accepts multiple computer names and supports pipeline input.

    .PARAMETER Credential
        Windows credential with administrative access to target computers.
        Required for remote deployment and must have permissions to write to PowerShell module directories.

    .PARAMETER SourcePath
        Path to dbatools module to copy. Supports:
        - Local module path (e.g., C:\Program Files\WindowsPowerShell\Modules\dbatools)
        - UNC path (e.g., \\fileserver\Software\dbatools)
        - Path to a specific version folder
        If not specified, uses the currently loaded dbatools module location.

    .PARAMETER UseAdminShare
        Uses admin shares (\\server\C$\) to copy files instead of PowerShell remoting.
        Use this when PSRemoting is not available or cannot be enabled on target servers.
        
        Limitations:
        - Cannot verify module loads correctly (no remote execution capability)
        - Requires admin access to C$ share on target computer
        - Files must not be in use (module not loaded) for successful copy
        - Assumes Windows PowerShell installation path
        
        Advantages:
        - Works without Enable-PSRemoting
        - Faster for simple file copy operations
        - Suitable for air-gapped environments with restrictive security policies

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Module, Installation, Deployment, Update, dbatools
        Author: Community contribution
        
        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires:
        - PowerShell Remoting enabled on target computers (unless -UseAdminShare is specified)
        - Administrative access to target computers
        - Network connectivity to target computers
        - Sufficient disk space on target computers (~100MB)

    .LINK
        https://dbatools.io/Update-DbaToolsModule

    .EXAMPLE
        PS C:\> Update-DbaToolsModule -ComputerName SQL01, SQL02, SQL03

        Copies the currently loaded dbatools module to SQL01, SQL02, and SQL03 using PSRemoting.

    .EXAMPLE
        PS C:\> Update-DbaToolsModule -ComputerName SQL01 -UseAdminShare

        Copies dbatools to SQL01 using admin share (\\SQL01\C$\) instead of PSRemoting.
        Useful when PowerShell remoting is not available.

    .EXAMPLE
        PS C:\> Update-DbaToolsModule -ComputerName SQL01 -SourcePath \\fileserver\Software\dbatools\2.7.12

        Copies dbatools version 2.7.12 from a file share to SQL01.

    .EXAMPLE
        PS C:\> Get-Content C:\servers.txt | Update-DbaToolsModule -UseAdminShare

        Reads server names from a file and updates dbatools on each using admin share method.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance CMS | Update-DbaToolsModule -UseAdminShare

        Updates dbatools on all servers registered in Central Management Server using admin share method.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('cn', 'host', 'Server', 'SqlInstance')]
        [string[]]$ComputerName,

        [PSCredential]$Credential,

        [string]$SourcePath,

        [switch]$UseAdminShare,

        [switch]$EnableException
    )

    begin {
        # Helper functions for standalone use (when dbatools private functions aren't available)
        if (-not (Get-Command Stop-Function -ErrorAction SilentlyContinue)) {
            function Stop-Function {
                param($Message, $Continue, $ErrorRecord)
                if ($EnableException) {
                    if ($ErrorRecord) {
                        throw $ErrorRecord
                    } else {
                        throw $Message
                    }
                } else {
                    Write-Warning $Message
                }
            }
        }

        if (-not (Get-Command Write-Message -ErrorAction SilentlyContinue)) {
            function Write-Message {
                param($Level, $Message)
                switch ($Level) {
                    'Output' { Write-Host $Message }
                    'Verbose' { Write-Verbose $Message }
                    'Warning' { Write-Warning $Message }
                    default { Write-Verbose $Message }
                }
            }
        }

        if (-not (Get-Command Test-FunctionInterrupt -ErrorAction SilentlyContinue)) {
            function Test-FunctionInterrupt {
                return $false
            }
        }

        # Get source
        if ($SourcePath) {
            $source = $SourcePath
        } else {
            $mod = Get-Module dbatools
            if (-not $mod) {
                Stop-Function -Message "dbatools module is not loaded and no SourcePath specified. Please load dbatools or specify -SourcePath"
                return
            }
            $source = Split-Path $mod.Path
        }

        if (-not (Test-Path $source)) {
            Stop-Function -Message "Source path not found: $source"
            return
        }

        # Get version
        $manifest = Join-Path $source "dbatools.psd1"
        if (Test-Path $manifest) {
            try {
                $ver = (Import-PowerShellDataFile $manifest).ModuleVersion
                Write-Message -Level Output -Message "Deploying dbatools version: $ver"
            } catch {
                Stop-Function -Message "Could not read module manifest" -ErrorRecord $_
                return
            }
        } else {
            Stop-Function -Message "Module manifest not found: $manifest"
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($computer in $ComputerName) {
            # Handle both string and DbaInstanceParameter types
            if ($computer -is [string]) {
                $comp = $computer
            } else {
                $comp = $computer.ComputerName
            }
            
            Write-Message -Level Verbose -Message "Processing $comp"
            
            if (-not (Test-Connection $comp -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                Stop-Function -Message "[$comp] Computer is not reachable" -Continue
            }

            if ($UseAdminShare) {
                # Admin share method
                $target = "\\$comp\C$\Program Files\WindowsPowerShell\Modules\dbatools\$ver"
                
                Write-Message -Level Verbose -Message "[$comp] Using admin share: $target"
                
                if (-not (Test-Path "\\$comp\C$" -ErrorAction SilentlyContinue)) {
                    Stop-Function -Message "[$comp] Cannot access admin share. Verify admin access and C$ share is available." -Continue
                }

                if ($PSCmdlet.ShouldProcess($comp, "Deploy dbatools version $ver via admin share")) {
                    try {
                        if (-not (Test-Path $target)) {
                            $null = New-Item $target -ItemType Directory -Force -ErrorAction Stop
                        }
                        
                        Write-Message -Level Output -Message "[$comp] Copying dbatools files via admin share..."
                        Copy-Item "$source\*" $target -Recurse -Force -ErrorAction Stop
                        
                        if (Test-Path "$target\dbatools.psd1") {
                            Write-Message -Level Output -Message "[$comp] Successfully deployed version $ver"
                            Write-Message -Level Warning -Message "[$comp] Cannot verify module loads correctly (no remote execution capability)"
                            
                            [PSCustomObject]@{
                                ComputerName     = $comp
                                Status           = 'Success'
                                Version          = $ver
                                Method           = 'AdminShare'
                                Path             = $target
                                RemoteVerified   = $false
                            }
                        } else {
                            Stop-Function -Message "[$comp] Module manifest not found after copy" -Continue
                        }
                    } catch {
                        Stop-Function -Message "[$comp] Failed to copy files via admin share" -ErrorRecord $_ -Continue
                    }
                }
            } else {
                # PSRemoting method
                Write-Message -Level Verbose -Message "[$comp] Testing PowerShell remoting"
                try {
                    $null = Test-WSMan $comp -ErrorAction Stop
                } catch {
                    Stop-Function -Message "[$comp] PowerShell remoting not available. Run 'Enable-PSRemoting' on target or use -UseAdminShare switch" -Continue
                }

                $sess = $null
                try {
                    Write-Message -Level Verbose -Message "[$comp] Creating remote session"
                    $sessParams = @{ComputerName = $comp; ErrorAction = 'Stop'}
                    if ($Credential) { $sessParams.Credential = $Credential }
                    
                    $sess = New-PSSession @sessParams
                    
                    if ($PSCmdlet.ShouldProcess($comp, "Deploy dbatools version $ver via PSRemoting")) {
                        $target = Invoke-Command $sess {
                            "$env:ProgramFiles\WindowsPowerShell\Modules\dbatools\$using:ver"
                        }
                        
                        Invoke-Command $sess {
                            param($t)
                            if (-not (Test-Path $t)) {
                                $null = New-Item $t -ItemType Directory -Force
                            }
                        } -ArgumentList $target
                        
                        Write-Message -Level Output -Message "[$comp] Copying dbatools files via PSRemoting..."
                        Write-Message -Level Verbose -Message "[$comp] Source: $source"
                        Write-Message -Level Verbose -Message "[$comp] Target: $target"
                        
                        Get-ChildItem $source -Recurse -File | ForEach-Object {
                            $rel = $_.FullName.Substring($source.Length).TrimStart('\')
                            $dest = Join-Path $target $rel
                            $destDir = Split-Path $dest
                            
                            Invoke-Command $sess {
                                param($d)
                                if (-not (Test-Path $d)) {
                                    $null = New-Item $d -ItemType Directory -Force
                                }
                            } -ArgumentList $destDir
                            
                            Copy-Item $_.FullName -ToSession $sess -Destination $dest -Force
                        }
                        
                        # Verify installation
                        Write-Message -Level Verbose -Message "[$comp] Verifying installation"
                        $verification = Invoke-Command $sess {
                            param($t)
                            $manifestPath = Join-Path $t "dbatools.psd1"
                            if (Test-Path $manifestPath) {
                                try {
                                    Import-Module $t -Force -ErrorAction Stop -WarningAction SilentlyContinue
                                    $mod = Get-Module dbatools
                                    return @{
                                        Success = $true
                                        Version = $mod.Version.ToString()
                                    }
                                } catch {
                                    return @{
                                        Success = $false
                                        Error   = $_.Exception.Message
                                    }
                                }
                            } else {
                                return @{
                                    Success = $false
                                    Error   = "Manifest not found"
                                }
                            }
                        } -ArgumentList $target
                        
                        if ($verification.Success) {
                            Write-Message -Level Output -Message "[$comp] Successfully deployed and verified version $($verification.Version)"
                            
                            [PSCustomObject]@{
                                ComputerName   = $comp
                                Status         = 'Success'
                                Version        = $verification.Version
                                Method         = 'PSRemoting'
                                Path           = $target
                                RemoteVerified = $true
                            }
                        } else {
                            Stop-Function -Message "[$comp] Module verification failed: $($verification.Error)" -Continue
                        }
                    }
                } catch {
                    Stop-Function -Message "[$comp] Failed to deploy via PSRemoting" -ErrorRecord $_ -Continue
                } finally {
                    if ($sess) { 
                        Write-Message -Level Verbose -Message "[$comp] Cleaning up remote session"
                        Remove-PSSession $sess -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}
