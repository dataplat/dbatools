function Install-DbaDarlingData {
    <#
    .SYNOPSIS
        Installs or updates Erik Darling's stored procedures.

    .DESCRIPTION
        Downloads, extracts and installs Erik Darling's stored procedures

        DarlingData links:
        https://www.erikdarlingdata.com
        https://github.com/erikdarlingdata/DarlingData

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install Erik's stored procedures into

    .PARAMETER Branch
        Specifies an alternate branch of Erik's to install.
        Allowed values:
            master (default)
            dev

    .PARAMETER Procedure
        Specifies the name(s) of the procedures to install
        Allowed Values or Combination of Values:
            All (default, to install all 3 procedures)
            Human (to install sp_HumanEvents)
            Pressure (to install sp_PressureDetector)
            Quickie (to install sp_QuickieStore)

    .PARAMETER LocalFile
        Specifies the path to a local file to install from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/erikdarlingdata/DarlingData

    .PARAMETER Force
        If this switch is enabled, the zip will be downloaded from the internet even if previously cached.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, Erik Darling, DarlingData
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaDarlingData

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1 -Database master

        Logs into server1 with Windows authentication and then installs all of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs tall of Erik's scripts in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database master -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs all of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs al of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance sql2016 -Branch dev

        Installs the dev branch version of Erik's scripts in the master database on sql2016 instance.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database DBA -Procedure Human, Pressure

        Logs into server1\instance1 with Windows authentication and then installs sp_HumanEvents and sp_PressureDetector of Erik's scripts in the DBA database.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object]$Database = "master",
        [ValidateSet('master', 'dev')]
        [string]$Branch = "master",
        [ValidateSet('All', 'Human', 'Pressure', 'Quickie')]
        [string[]]$Procedure = "All",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        if (-not $DbatoolsData) {
            $DbatoolsData = [System.IO.Path]::GetTempPath()
        }

        $url = "https://github.com/erikdarlingdata/DarlingData/archive/$Branch.zip"
        $temp = [System.IO.Path]::GetTempPath()
        $zipFile = Join-Path -Path $temp -ChildPath "DarlingData-$Branch.zip"
        $zipFolder = Join-Path -Path $temp -ChildPath "DarlingData-$Branch"
        $LocalCachedCopy = Join-Path -Path $DbatoolsData -ChildPath "DarlingData-$Branch"

        if ($Force -or -not(Test-Path -Path $LocalCachedCopy -PathType Container) -or $LocalFile) {
            # Force was passed, or we don't have a local copy, or $LocalFile was passed
            if (Test-Path $zipFile) {
                if ($PSCmdlet.ShouldProcess($zipFile, "File found, dropping $zipFile")) {
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                }
            }

            if ($LocalFile) {
                if (-not (Test-Path $LocalFile)) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "File does not exists, returning to prompt")) {
                        Stop-Function -Message "$LocalFile doesn't exist"
                        return
                    }
                }
                if (Test-Path $LocalFile -PathType Container) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "File is not a zip file, returning to prompt")) {
                        Stop-Function -Message "$LocalFile should be a zip file"
                        return
                    }
                }
                if (Test-Windows -NoWarn) {
                    if ($PSCmdlet.ShouldProcess($LocalFile, "Checking if Windows system, unblocking file")) {
                        Unblock-File $LocalFile -ErrorAction SilentlyContinue
                    }
                }
                if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $temp path")) {
                    Expand-Archive -Path $LocalFile -DestinationPath $temp -Force
                }
            } else {
                Write-Message -Level Verbose -Message "Downloading and unzipping the DarlingData zip file."
                if ($PSCmdlet.ShouldProcess($url, "Downloading zip file")) {
                    try {
                        try {
                            Invoke-TlsWebRequest $url -OutFile $zipFile -ErrorAction Stop -UseBasicParsing
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            Invoke-TlsWebRequest $url -OutFile $zipFile -ErrorAction Stop -UseBasicParsing
                        }

                        # Unblock if there's a block
                        if (Test-Windows -NoWarn) {
                            Unblock-File $zipFile -ErrorAction SilentlyContinue
                        }

                        Expand-Archive -Path $zipFile -DestinationPath $temp -Force
                        Remove-Item -Path $zipFile
                    } catch {
                        Stop-Function -Message "Couldn't download the DarlingData-$Branch.zip file. Download and install manually from https://github.com/erikdarlingdata/DarlingData/archive/$Branch.zip." -ErrorRecord $_
                        return
                    }
                }
            }

            ## Copy it into local area
            if ($PSCmdlet.ShouldProcess("LocalCachedCopy", "Copying extracted files to the local module cache")) {
                if (Test-Path -Path $LocalCachedCopy -PathType Container) {
                    Remove-Item -Path (Join-Path $LocalCachedCopy '*') -Recurse -ErrorAction SilentlyContinue
                } else {
                    $null = New-Item -Path $LocalCachedCopy -ItemType Container
                }
                if ($Procedure -eq 'All' -or $Procedure -contains 'Human') {
                    Copy-Item -Path "$zipFolder\sp_humanevents\sp_humanevents.sql" -Destination $LocalCachedCopy
                }
                if ($procedure -eq 'All' -or $Procedure -contains 'Pressure') {
                    Copy-Item -Path "$zipFolder\sp_pressuredetector\sp_pressuredetector.sql" -Destination $LocalCachedCopy
                }
                if ($Procedure -eq 'All' -or $Procedure -contains 'Quickie') {
                    Copy-Item -Path "$zipFolder\sp_quickiestore\sp_quickiestore.sql" -Destination $LocalCachedCopy
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }

            $db = $server.Databases[$Database]
            if ($null -eq $db) {
                Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue
            }

            if ($PSCmdlet.ShouldProcess($database, "Installing DarlingData procedures in $database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating the DarlingData stored procedures in $database on $instance."
                $allprocedures_query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0"
                $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

                # Install/Update each FRK stored procedure

                $sqlScripts = Get-ChildItem $LocalCachedCopy -Filter "sp_*.sql"

                foreach ($script in $sqlScripts) {
                    $sql = Get-Content $script.FullName -Raw
                    $scriptName = $script.Name
                    $scriptError = $false

                    $baseres = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = $script.BaseName
                        Status       = $null
                    }

                    if ($scriptName -eq "sp_QuickieStore.sql" -and ($server.VersionMajor -lt 13)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping $scriptName"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database")) {
                        try {
                            foreach ($query in ($sql -Split "\nGO\b")) {
                                $null = $db.Query($query)
                            }
                        } catch {
                            Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_
                            $scriptError = $true
                        }

                        if ($scriptError) {
                            $baseres.Status = 'Error'
                        } elseif ($script.BaseName -in $allprocedures) {
                            $baseres.Status = 'Updated'
                        } else {
                            $baseres.Status = 'Installed'
                        }
                        $baseres
                    }
                }
            }
            Write-Message -Level Verbose -Message "Finished installing/updating the DarlingData stored procedures in $database on $instance."
        }
    }
}