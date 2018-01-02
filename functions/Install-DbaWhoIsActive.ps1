function Install-DbaWhoIsActive {
    <#
        .SYNOPSIS
            Automatically installs or updates sp_WhoisActive by Adam Machanic.

        .DESCRIPTION
            This command downloads, extracts and installs sp_WhoisActive with Adam's permission. To read more about sp_WhoisActive, please visit http://whoisactive.com and http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

            Please consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

            Note that you will be prompted a bunch of times to confirm an action.

        .PARAMETER SqlInstance
            The SQL Server instance. Server version must be SQL Server version 2005 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database to install sp_WhoisActive into. This parameter is mandatory when executing this command unattended.

        .PARAMETER LocalFile
            Specifies the path to a local file to install sp_WhoisActive from. This can be either the zipfile as distributed by the website or the expanded SQL script. If this parameter is not specified, the latest version will be downloaded and installed from https://whoisactive.com/

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Force
            If this switch is enabled, the sp_WhoisActive will be downloaded from the internet even if previously cached.

        .EXAMPLE
            Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master

            Downloads sp_WhoisActive from the internet and installs to sqlserver2014a's master database. Connects to SQL Server using Windows Authentication.

        .EXAMPLE
            Install-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $cred

            Pops up a dialog box asking which database on sqlserver2014a you want to install the procedure into. Connects to SQL Server using SQL Authentication.

        .EXAMPLE
            Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master -LocalFile c:\SQLAdmin\whoisactive_install.sql

            Installs sp_WhoisActive to sqlserver2014a's master database from the local file whoisactive_install.sql

        .EXAMPLE
            $instances = Get-DbaRegisteredServer sqlserver
            Install-DbaWhoIsActive -SqlInstance $instances -Database master

        .NOTES
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Install-DbaWhoIsActive
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PsCredential]$SqlCredential,
        [parameter(Mandatory = $false)]
        [ValidateScript( { Test-Path -Path $_ -PathType Leaf })]
        [string]$LocalFile,
        [object]$Database,
        [switch][Alias('Silent')]
        $EnableException,
        [switch]$Force
    )

    begin {
        $DbatoolsData = Get-DbaConfigValue -FullName "Path.DbatoolsData"
        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $zipfile = "$temp\spwhoisactive.zip"

        if ($LocalFile -eq $null -or $LocalFile.Length -eq 0) {
            $baseUrl = "http://whoisactive.com/downloads"
            $latest = ((Invoke-WebRequest -UseBasicParsing -uri http://whoisactive.com/downloads).Links | where-object { $PSItem.href -match "who_is_active" } | Select-Object href -First 1).href
            $LocalCachedCopy = Join-Path -Path $DbatoolsData -ChildPath $latest;

            if ((Test-Path -Path $LocalCachedCopy -PathType Leaf) -and (-not $Force)) {
                Write-Message -Level Verbose -Message "Locally-cached copy exists, skipping download."
                if ($PSCmdlet.ShouldProcess($env:computername, "Copying sp_WhoisActive from local cache for installation")) {
                    Copy-Item -Path $LocalCachedCopy -Destination $zipfile;
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess($env:computername, "Downloading sp_WhoisActive")) {
                    try {
                        Write-Message -Level Verbose -Message "Downloading sp_WhoisActive zip file, unzipping and installing."
                        $url = $baseUrl + "/" + $latest
                        try {
                            Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                            Copy-Item -Path $zipfile -Destination $LocalCachedCopy
                        }
                        catch {
                            #try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            Invoke-WebRequest $url -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                        }
                    }
                    catch {
                        Stop-Function -Message "Couldn't download sp_WhoisActive. Please download and install manually from $url." -ErrorRecord $_
                        return
                    }
                }
            }
        }
        else {
            # Look local
            if ($PSCmdlet.ShouldProcess($env:computername, "Copying local file to temp directory")) {

                if ($LocalFile.EndsWith("zip")) {
                    Copy-Item -Path $LocalFile -Destination $zipfile -Force
                }
                else {
                    Copy-Item -Path $LocalFile -Destination (Join-Path -path $temp -childpath "whoisactivelocal.sql")
                }
            }
        }
        if ($LocalFile -eq $null -or $LocalFile.Length -eq 0 -or $LocalFile.EndsWith("zip")) {
            # Unpack
            # Unblock if there's a block
            if ($PSCmdlet.ShouldProcess($env:computername, "Unpacking zipfile")) {

                Unblock-File $zipfile -ErrorAction SilentlyContinue

                if (Get-Command -ErrorAction SilentlyContinue -Name "Expand-Archive") {
                    try {
                        Expand-Archive -Path $zipfile -DestinationPath $temp -Force
                    }
                    catch {
                        Stop-Function -Message "Unable to extract $zipfile. Archive may not be valid." -ErrorRecord $_
                        return
                    }
                }
                else {
                    # Keep it backwards compatible
                    $shell = New-Object -ComObject Shell.Application
                    $zipPackage = $shell.NameSpace($zipfile)
                    $destinationFolder = $shell.NameSpace($temp)
                    Get-ChildItem "$temp\who*active*.sql" | Remove-Item
                    $destinationFolder.CopyHere($zipPackage.Items())
                }
                Remove-Item -Path $zipfile
            }
            $sqlfile = (Get-ChildItem "$temp\who*active*.sql" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }
        else {
            $sqlfile = $LocalFile
        }

        if ($PSCmdlet.ShouldProcess($env:computername, "Reading SQL file into memory")) {
            Write-Message -Level Verbose -Message "Using $sqlfile."

            $sql = [IO.File]::ReadAllText($sqlfile)
            $sql = $sql -replace 'USE master', ''
            $batches = $sql -split "GO\r\n"
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $Database) {
                if ($PSCmdlet.ShouldProcess($instance, "Prompting with GUI list of databases")) {
                    $Database = Show-DbaDatabaseList -SqlInstance $server -Title "Install sp_WhoisActive" -Header "To deploy sp_WhoisActive, select a database or hit cancel to quit." -DefaultDb "master"

                    if (-not $Database) {
                        Stop-Function -Message "You must select a database to install the procedure." -Target $Database
                        return
                    }

                    if ($Database -ne 'master') {
                        Write-Message -Level Warning -Message "You have selected a database other than master. When you run Invoke-DbaWhoIsActive in the future, you must specify -Database $Database."
                    }
                }
            }
            if ($PSCmdlet.ShouldProcess($instance, "Installing sp_WhoisActive")) {
                try {
                    $ProcedureExists_Query = "select COUNT(*) [proc_count] from sys.procedures where is_ms_shipped = 0 and name like '%sp_WhoisActive%'"

                    if ($server.Databases[$Database]) {
                        $ProcedureExists = ($server.Query($ProcedureExists_Query, $Database)).proc_count
                        foreach ($batch in $batches) {
                            try {
                                $null = $server.databases[$Database].ExecuteNonQuery($batch)
                            }
                            catch {
                                Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance
                            }
                        }

                        if ($ProcedureExists -gt 0) {
                            $status = 'Updated'
                        }
                        else {
                            $status = 'Installed'
                        }
                        [PSCustomObject]@{
                            ComputerName = $server.NetName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $Database
                            Name         = 'sp_WhoisActive'
                            Status       = $status
                        }
                    }
                    else {
                        Stop-Function -Message "Failed to find database $Database on $instance or $Database is not writeable." -ErrorRecord $_ -Continue -Target $instance
                    }

                }
                catch {
                    Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance
                }

            }
        }
    }
    end {
        if ($PSCmdlet.ShouldProcess($env:computername, "Post-install cleanup")) {
            Get-Item $sqlfile | Remove-Item
        }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Install-SqlWhoIsActive
    }
}
