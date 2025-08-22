function Install-DbaMultiTool {
    <#
    .SYNOPSIS
        Installs five essential T-SQL stored procedures for database documentation, index optimization, and administrative tasks.

    .DESCRIPTION
        Downloads and installs the DBA MultiTool collection of T-SQL stored procedures into a specified database. This toolkit provides five key utilities that help DBAs with common documentation and optimization tasks that would otherwise require manual T-SQL scripting.

        The installed procedures include:
        • sp_helpme - Enhanced version of sp_help that provides detailed object information
        • sp_doc - Generates comprehensive database documentation
        • sp_sizeoptimiser - Analyzes and recommends optimal database file sizing
        • sp_estindex - Estimates potential storage savings from index compression
        • sp_help_revlogin - Creates scripts to recreate logins with their original SIDs and passwords

        These procedures are particularly valuable for database migrations, compliance reporting, capacity planning, and general administrative documentation. The function automatically handles downloading the latest version from GitHub and can install across multiple instances simultaneously.

        DBA MultiTool links:
        https://dba-multitool.org
        https://github.com/LowlyDBA/dba-multitool/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install DBA MultiTool stored procedures into.

    .PARAMETER Branch
        Specifies an alternate branch of the DBA MultiTool to install.
        Allowed values:
            main (default)
            development

    .PARAMETER LocalFile
        Specifies the path to a local file to install DBA MultiTool from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/LowlyDBA/dba-multitool/.

    .PARAMETER Force
        If this switch is enabled, the DBA MultiTool will be downloaded from the internet even if previously cached.

    .PARAMETER Confirm
        Prompts to confirm actions.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, DbaMultiTool
        Author: John McCall (@lowlydba), lowlydba.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://dba-multitool.org

    .LINK
        https://dbatools.io/Install-DbaMultiTool

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1 -Database main

        Logs into server1 with Windows authentication and then installs the DBA MultiTool in the main database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs the DBA MultiTool in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance server1\instance1 -Database main -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs the DBA MultiTool in the main database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the DBA MultiTool in the main database.

    .EXAMPLE
        PS C:\> $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
        PS C:\> $servers | Install-DbaMultiTool

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the DBA MultiTool in the main database.

    .EXAMPLE
        PS C:\> Install-DbaMultiTool -SqlInstance sql2016 -Branch development

        Installs the development branch version of the DBA MultiTool in the main database on sql2016 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('main', 'development')]
        [string]$Branch = "main",
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "dba-multitool-$Branch"
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('DbaMultiTool', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software DbaMultiTool -Branch $Branch -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($PSCmdlet.ShouldProcess($Database, "Installing DbaMultiTool procedures in $Database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating DbaMultiTool stored procedures in $Database on $instance."
                $allProcedures_Query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0;"
                $allProcedures = ($server.Query($allProcedures_Query, $Database)).Name

                # We only install specific scripts
                $sqlScripts = @( )
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_helpme.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_doc.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_sizeoptimiser.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_estindex.sql" -Recurse
                $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_help_revlogin.sql" -Recurse

                foreach ($script in $sqlScripts) {
                    $scriptName = $script.Name
                    $scriptError = $false

                    $baseRes = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = $script.BaseName
                        Status       = $null
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $Database")) {
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                        } catch {
                            Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_
                            $scriptError = $true
                        }

                        if ($scriptError) {
                            $baseRes.Status = 'Error'
                        } elseif ($script.BaseName -in $allProcedures) {
                            $baseRes.Status = 'Updated'
                        } else {
                            $baseRes.Status = 'Installed'
                        }
                        $baseRes
                    }
                }
            }
            Write-Message -Level Verbose -Message "Finished installing/updating DbaMultiTool stored procedures in $Database on $instance."
        }
    }
}