function Remove-DbaDbData {
    <#
    .SYNOPSIS
        Truncates all user tables in specified databases to remove all data while preserving table structure.

    .DESCRIPTION
        Removes all data from user tables by truncating each table in the specified databases. When foreign keys or views exist that would prevent truncation, the function automatically scripts them out, drops them temporarily, performs the truncation, then recreates the objects with their original definitions and permissions. This provides a fast way to clear databases for testing or development environments without having to rebuild schemas. The function excludes system databases and only processes user databases to prevent accidental damage to SQL Server internals.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to clear of data. Accepts wildcards for pattern matching.
        When omitted, the function processes all user databases on the instance. System databases are always excluded for safety.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from data removal operations. Use this to protect important databases when clearing multiple databases.
        Commonly used with production or reference databases that should remain untouched during development environment resets.

    .PARAMETER InputObject
        Accepts piped database objects from Get-DbaDatabase or server connections from Connect-DbaInstance.
        Use this for pipeline operations when you need to filter databases with complex criteria before clearing data.

    .PARAMETER Path
        Sets the temporary directory for storing drop and create scripts during the data removal process.
        The function creates temporary SQL scripts for foreign keys and views, then automatically removes them when complete. Defaults to the configured dbatools export path.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Data
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbData

    .EXAMPLE
        PS C:\> Remove-DbaDbData -SqlInstance localhost -Database dbname

        Removes all data from the dbname database on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbData -SqlInstance mssql1 -ExcludeDatabase DBA -Confirm:$False

        Removes all data from all databases on mssql1 except the DBA Database. Doesn't prompt for confirmation.

    .EXAMPLE
        PS C:\> $svr = Connect-DbaInstance -SqlInstance mssql1
        PS C:\> $svr | Remove-DbaDbData -Database AdventureWorks2017

        Removes all data from AdventureWorks2017 on the mssql1 SQL Server Instance, uses piped input from Connect-DbaInstance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance mssql1 -Database AdventureWorks2017 | Remove-DbaDbData

        Removes all data from AdventureWorks2017 on the mssql1 SQL Server Instance, uses piped input from Get-DbaDatabase.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$EnableException
    )

    begin {
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or a server, or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbDatabases = $input | Where-Object { -not $_.IsSystemObject }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or database."
                    return
                }
            }

            foreach ($db in $dbDatabases) {
                if ($Pscmdlet.ShouldProcess($db.Name, "Removing all data on $($db.Parent.Name)")) {
                    $server = $db.Parent
                    Write-Message -Level Verbose -Message "Truncating tables in $db on instance $server"
                    try {

                        # Collect up the objects we need to drop and recreate
                        $objects = @()
                        $objects += Get-DbaDbForeignKey -SqlInstance $server -Database $db.Name
                        $objects += Get-DbaDbView -SqlInstance $server -Database $db.Name -ExcludeSystemView

                        # Script out the create statements for objects
                        $createOptions = New-DbaScriptingOption
                        $createOptions.Permissions = $true
                        $createOptions.ScriptBatchTerminator = $true
                        $createOptions.AnsiFile = $true
                        $null = $objects | Export-DbaScript -FilePath "$Path\$($db.Name)_Create.Sql" -ScriptingOptionsObject $createOptions

                        # Script out the drop statements for objects
                        $dropOptions = New-DbaScriptingOption
                        $dropOptions.ScriptDrops = $true
                        $null = $objects | Export-DbaScript -FilePath "$Path\$($db.Name)_Drop.Sql" -ScriptingOptionsObject $dropOptions
                    } catch {
                        Stop-Function -Message "Issue scripting out the drop\create scripts for objects in $db on instance $server" -ErrorRecord $_
                        return
                    }

                    try {
                        if ($objects) {
                            Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Drop.Sql"
                        }

                        $db.Tables | ForEach-Object { $_.TruncateData() }

                        if ($objects) {
                            Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                        }
                    } catch {
                        Write-Message -Level warning -Message "Issue truncating tables in $db on instance $server"
                        Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                    }
                    if ($objects) {
                        try {
                            Remove-Item "$Path\$($db.Name)_Drop.Sql", "$Path\$($db.Name)_Create.Sql" -ErrorAction Stop
                        } catch {
                            Write-Message -Level warning -Message "Unable to clear up output files for $db on $server"
                        }
                    }
                }
            }
        }
    }
}