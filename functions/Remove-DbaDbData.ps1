function Remove-DbaDbData {
    <#
    .SYNOPSIS
        Removes all the data from a database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        This command truncates all the tables in a database. If there are foreign keys and/or views they are scripted out, then dropped before the truncate, and recreated after.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all user databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Database
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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
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
                    Write-Message -Level Verbose -Message "Truncating tables in $db on instance $instance"
                    $instance = $db.Parent
                    try {

                        # Collect up the objects we need to drop and recreate
                        $objects = @()
                        $objects += Get-DbaDbForeignKey -SqlInstance $instance -Database $db.Name
                        $objects += Get-DbaDbView -SqlInstance $instance -Database $db.Name -ExcludeSystemView

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
                        Stop-Function -Message "Issue scripting out the drop\create scripts for objects in $db on instance $instance" -ErrorRecord $_
                        return
                    }

                    try {
                        if ($objects) {
                            Invoke-DbaQuery -SqlInstance $instance -Database $db.Name -File "$Path\$($db.Name)_Drop.Sql"
                        }

                        $db.Tables | ForEach-Object { $_.TruncateData() }

                        if ($objects) {
                            Invoke-DbaQuery -SqlInstance $instance -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                        }
                    } catch {
                        Write-Message -Level warning -Message "Issue truncating tables in $db on instance $instance"
                        Invoke-DbaQuery -SqlInstance $instance -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                    }
                    if ($objects) {
                        try {
                            Remove-Item "$Path\$($db.Name)_Drop.Sql", "$Path\$($db.Name)_Create.Sql" -ErrorAction Stop
                        } catch {
                            Write-Message -Level warning -Message "Unable to clear up output files for $instance.$db"
                        }
                    }
                }
            }
        }
    }
}