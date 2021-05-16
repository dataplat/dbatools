function Remove-DbaDbView {
    <#
    .SYNOPSIS
        Removes a database view from database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbView removes view(s) from database(s) for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER View
        The view(s) to process. If unspecified, all views will be processed.

    .PARAMETER IncludeSystemDbs
        If this switch is enabled, views can be removed from system databases.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDbView or Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: View, Database
        Author: Mikey Bronowski (@MikeyBronowski), https://bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbView

    .EXAMPLE
        PS C:\> Remove-DbaDbView -SqlInstance localhost -Database dbname -View "customview1", "customview2"

        Removes views customview1 and customview2 from the database dbname on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Remove-DbaDbView -SqlInstance localhost, sql2016 -Database db1, db2 -View view1, view2, view3

        Removes view1, view2, view3 from db1 and db2 on the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> Remove-DbaDbView -SqlInstance localhost -Database msdb -IncludeSystemDbs -View view1, view2, view3

        Removes view1, view2, view3 from db1 and db2 from system database (msdb) on the local SQL Server instances.

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbView -Database db1, db2 -View view1

        Removes view1 from db1 and db2 on the servers in C:\servers.txt file.

    .EXAMPLE
        PS C:\> $views = Get-DbaDbView -SqlInstance localhost, sql2016 -Database db1, db2 -View view1, view2, view3
        PS C:\> $views | Remove-DbaDbView

        Removes view1, view2, view3 from db1 and db2 on the local and sql2016 SQL Server instances.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$View,
        [switch]$IncludeSystemDbs,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a view, database, or server or specify a SqlInstance"
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
                    $dbViews = Get-DbaDbView -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -View $View
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbViews = Get-DbaDbView -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -View $View
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbViews | Get-DbaDbView -InputObject $input
                }
                'Microsoft.SqlServer.Management.Smo.View' {
                    Write-Message -Level Verbose -Message "Processing DatabaseView through InputObject"
                    $dbViews = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database view."
                    return
                }
            }

            foreach ($dbView in $dbViews) {
                $db = $dbView.Parent
                $instance = $db.Parent
                if ((!$db.IsSystemObject) -or ($db.IsSystemObject -and $IncludeSystemDbs )) {
                    if (!$dbView.IsSystemObject) {
                        if ($PSCmdlet.ShouldProcess($instance, "Remove view $dbView from database $db")) {
                            $dbView.Drop()

                        }
                    } else {
                        Write-Message -Level Verbose -Message "Cannot remove fixed view $dbView from database $db on instance $instance"
                    }
                } else {
                    Write-Message -Level Verbose -Message "Can only remove views from System database when IncludeSystemDbs switch used."
                }
            }
        }
    }
}