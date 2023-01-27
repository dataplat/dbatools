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
            main (default)
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
        [ValidateSet('main', 'dev')]
        [string]$Branch = "main",
        [ValidateSet('All', 'Human', 'Pressure', 'Quickie')]
        [string[]]$Procedure = "All",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "DarlingData-$Branch"
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('DarlingData', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software DarlingData -Branch $Branch -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

                # We only install specific scripts that as located in different subdirectories and exclude the example
                $sqlScripts = @( )
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HumanEvents.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_PressureDetector.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_QuickieStore.sql" -Recurse

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