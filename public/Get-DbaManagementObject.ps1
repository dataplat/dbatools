function Get-DbaManagementObject {
    <#
    .SYNOPSIS
        Discovers installed SQL Server Management Object (SMO) assemblies and their load status

    .DESCRIPTION
        Scans the system for SQL Server Management Object (SMO) assemblies, SqlClient libraries, and SNI modules to help troubleshoot version conflicts and connectivity issues. This function checks both the Global Assembly Cache (GAC) and currently loaded assemblies in the PowerShell session, returning version information, load status, file paths, and ready-to-use Add-Type commands. Particularly useful when diagnosing why different SQL Server tools behave differently or when you need to load specific SMO versions in PowerShell scripts.

    .PARAMETER ComputerName
        Specifies the Windows server(s) where you want to scan for SMO assemblies and SQL Client libraries.
        Use this when troubleshooting SMO version conflicts across multiple servers or when checking which SQL Server tools are installed on remote machines.

    .PARAMETER Credential
        This command uses Windows credentials. This parameter allows you to connect remotely as a different user.

    .PARAMETER VersionNumber
        Filters results to show only assemblies matching the specified major version number (e.g., 13 for SQL Server 2016, 14 for 2017, 15 for 2019).
        Use this when you need to verify if a specific SQL Server version's SMO libraries are installed, particularly when troubleshooting version compatibility issues between different SQL Server tools.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SMO
        Author: Ben Miller (@DBAduck), dbaduck.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaManagementObject

    .EXAMPLE
        PS C:\> Get-DbaManagementObject

        Returns all versions of SMO on the computer

    .EXAMPLE
        PS C:\> Get-DbaManagementObject -VersionNumber 13

        Returns just the version specified. If the version does not exist then it will return nothing.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]
        $Credential,
        [int]$VersionNumber,
        [switch]$EnableException
    )

    begin {
        if (-not $VersionNumber) {
            $VersionNumber = 0
        }
        $scriptBlock = {
            $VersionNumber = [int]$args[0]
            $remote = $args[1]
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Checking currently loaded SMO, SqlClient, and related assemblies"
            $loadedassemblies = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" -or $_.Fullname -like "*.smo.*" -or $_.Fullname -like "*SqlClient*" -or $_.Fullname -like "*sqlclient*sni*" }
            $loadedversion = @()
            $loadedversionPath = $null
            if ($loadedassemblies) {
                Write-Verbose -Message "Found $($loadedassemblies.Count) loaded SQL-related assemblies: $($loadedassemblies.FullName -join ', ')"
                $loadedversion = $loadedassemblies | ForEach-Object {
                    # Extract version from assembly FullName (e.g., "Microsoft.SqlServer.Smo, Version=17.100.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91")
                    if ($_.FullName -match "Version=([^,]+)") {
                        $matches[1]
                    } elseif ($_.Location -match "__") {
                        ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                    } else {
                        ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                    }
                }
                $loadedversionPath = $loadedassemblies[0].Location
            } else {
                Write-Verbose -Message "No SQL-related assemblies currently loaded in AppDomain"
            }

            # Check for SNI modules loaded in the current process
            $sniModules = @()
            try {
                $sniModules = Get-Process -Id $PID | ForEach-Object {
                    $_.Modules | Where-Object { $_.ModuleName -like '*SNI*' }
                }
                if ($sniModules) {
                    Write-Verbose -Message "Found $($sniModules.Count) SNI modules: $($sniModules.ModuleName -join ', ')"
                }
            } catch {
                Write-Verbose -Message "Error checking for SNI modules: $($_.Exception.Message)"
            }

            if (-not $remote) {
                <# DO NOT use Write-Message as this is inside of a script block #>
                $liblocation = ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" -or $_.Fullname -like "*.smo.*" -or $_.Fullname -like "*SqlClient*" -or $_.Fullname -like "*sqlclient*sni*" } | Select-Object -First 1).Location

                Write-Verbose -Message "Looking for included smo library at $liblocation"
                $initialversion = (Get-ChildItem -Path $liblocation).VersionInfo.ProductVersion -split "\+" | Select-Object -First 1
                $localversion = [version]$initialversion

                foreach ($version in $localversion) {
                    if ($VersionNumber -eq 0) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Did not pass a version"
                        # Check if any loaded version matches this local version (compare major.minor versions)
                        $isLoaded = $false
                        foreach ($loadedVer in $loadedversion) {
                            $loadedVerObj = [version]$loadedVer
                            if ($loadedVerObj.Major -eq $localversion.Major -and $loadedVerObj.Minor -eq $localversion.Minor) {
                                $isLoaded = $true
                                break
                            }
                        }
                        [PSCustomObject]@{
                            ComputerName = [string]$env:COMPUTERNAME
                            Version      = [string]$localversion
                            Loaded       = [bool]$isLoaded
                            Path         = [string]$loadedversionPath
                            LoadTemplate = [string]("Add-Type -Path " + [string]$loadedversionPath)
                        }
                    } else {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                        if ($localversion.ToString().StartsWith("$VersionNumber.")) {

                            $loadedversionPath = $loadedversion.Location
                            <# DO NOT use Write-Message as this is inside of a script block #>
                            Write-Verbose -Message "Found the Version $VersionNumber"
                            # Check if any loaded version matches this local version (compare major.minor versions)
                            $isLoaded = $false
                            foreach ($loadedVer in $loadedversion) {
                                $loadedVerObj = [version]$loadedVer
                                if ($loadedVerObj.Major -eq $localversion.Major -and $loadedVerObj.Minor -eq $localversion.Minor) {
                                    $isLoaded = $true
                                    break
                                }
                            }
                            [PSCustomObject]@{
                                ComputerName = [string]$env:COMPUTERNAME
                                Version      = [string]$localversion
                                Loaded       = [bool]$isLoaded
                                Path         = [string]$loadedversionPath
                                LoadTemplate = [string]("Add-Type -Path " + [string]$loadedversionPath)
                            }
                        }
                    }
                }

                # Output loaded assemblies that don't have corresponding local files
                foreach ($assembly in $loadedassemblies) {
                    $assemblyVersion = ""
                    if ($assembly.FullName -match "Version=([^,]+)") {
                        $assemblyVersion = $matches[1]
                    }

                    # Check if this assembly version is already covered by local files
                    $alreadyCovered = $false
                    if ($assemblyVersion) {
                        $assemblyVerObj = [version]$assemblyVersion
                        if ($localversion -and $assemblyVerObj.Major -eq $localversion.Major -and $assemblyVerObj.Minor -eq $localversion.Minor) {
                            $alreadyCovered = $true
                        }
                    }

                    # Only output if not already covered by local file detection
                    if (-not $alreadyCovered -and $assemblyVersion) {
                        [PSCustomObject]@{
                            ComputerName = [string]$env:COMPUTERNAME
                            Version      = [string]$assemblyVersion
                            Loaded       = $true
                            Path         = [string]$assembly.Location
                            LoadTemplate = [string]("Add-Type -Path `"" + [string]$assembly.Location + "`"")
                        }
                    }
                }
            }

            <# DO NOT use Write-Message as this is inside of a script block #>
            if (-not $IsLinux -and -not $IsMacOs) {
                $smolist = (Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -ErrorAction Ignore | Sort-Object Name -Descending).Name
                $second = $false

                if (-not $smoList) {
                    $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction Ignore | Where-Object FullName -match "_$number" | Sort-Object Name -Descending).Name
                    $second = $true
                }

                if (-not $smolist) {
                    Write-Verbose -Message "No SMO versions found in GAC"
                    continue
                }

                foreach ($version in $smolist) {
                    if ($second) {
                        $array = $version.Split("_")
                        $currentversion = $array[1]
                    } else {
                        $array = $version.Split("__")
                        $currentversion = $array[0]
                    }
                    if ($VersionNumber -eq 0) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Did not pass a version, looking for all versions"

                        [PSCustomObject]@{
                            ComputerName = [string]$env:COMPUTERNAME
                            Version      = [string]$currentversion
                            Loaded       = [bool]($loadedversion -contains $currentversion)
                            Path         = $null
                            LoadTemplate = [string]("Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=" + [string]$currentversion + ", Culture=neutral, PublicKeyToken=89845dcd8080cc91`"")
                        }
                    } else {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                        if ($currentversion.StartsWith("$VersionNumber.")) {
                            <# DO NOT use Write-Message as this is inside of a script block #>
                            Write-Verbose -Message "Found the Version $VersionNumber"

                            [PSCustomObject]@{
                                ComputerName = [string]$env:COMPUTERNAME
                                Version      = [string]$currentversion
                                Loaded       = [bool]($loadedversion -contains $currentversion)
                                Path         = $null
                                LoadTemplate = [string]("Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=" + [string]$currentversion + ", Culture=neutral, PublicKeyToken=89845dcd8080cc91`"")
                            }
                        }

                    }
                }
            }

            # Output SNI modules found (always run this regardless of other conditions)
            foreach ($sniModule in $sniModules) {
                $moduleVersion = "Unknown"
                try {
                    if ($sniModule.FileVersionInfo -and $sniModule.FileVersionInfo.FileVersion) {
                        $moduleVersion = $sniModule.FileVersionInfo.FileVersion
                    }
                } catch {
                    # Ignore version extraction errors
                }

                # Find the corresponding SqlClient assembly for this SNI module by matching directory structure
                $sqlClientPath = ""
                $sniPath = $sniModule.FileName

                # Look for SqlClient in the same directory tree (usually parent of runtimes folder)
                $sqlClientAssembly = $loadedassemblies | Where-Object {
                    $_.FullName -like "*SqlClient*" -and
                    $sniPath -like "*$([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetDirectoryName($_.Location))))*"
                }

                if (-not $sqlClientAssembly) {
                    # Fallback: try to find SqlClient in parent directories of SNI path
                    $sniDir = [System.IO.Path]::GetDirectoryName($sniPath)
                    while ($sniDir -and -not $sqlClientAssembly) {
                        $sniDir = [System.IO.Path]::GetDirectoryName($sniDir)
                        $potentialSqlClientPath = Join-Path $sniDir "Microsoft.Data.SqlClient.dll"
                        $sqlClientAssembly = $loadedassemblies | Where-Object { $_.Location -eq $potentialSqlClientPath }
                    }
                }

                if ($sqlClientAssembly) {
                    $sqlClientPath = $sqlClientAssembly.Location
                }

                [PSCustomObject]@{
                    ComputerName = [string]$env:COMPUTERNAME
                    Version      = [string]$moduleVersion
                    Loaded       = $true
                    Path         = [string]$sniModule.FileName
                    LoadTemplate = if ($sqlClientPath) { [string]("Add-Type -Path `"" + [string]$sqlClientPath + "`" -ReferencedAssemblies `"" + [string]$sniModule.FileName + "`"") } else { "" }
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                if ($computer -eq $env:COMPUTERNAME -or $computer -eq "localhost") {
                    Write-Message -Level Verbose -Message "Executing scriptblock against $computer"
                    Invoke-Command -Scriptblock $scriptBlock -ErrorAction Stop
                } else {
                    Write-Message -Level Verbose -Message "Executing scriptblock against $computer"
                    Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptBlock -Credential $Credential -ArgumentList $VersionNumber, $true -ErrorAction Stop
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $ComputerName
            }
        }
    }
}