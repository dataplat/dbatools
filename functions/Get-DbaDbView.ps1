function Get-DbaDbView {
    <#
    .SYNOPSIS
        Gets database views for each SqlInstance.

    .DESCRIPTION
        Gets database views for each SqlInstance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        To get views from specific database(s) - this list is auto populated from the server.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto populated from the server.

    .PARAMETER ExcludeSystemView
        This switch removes all system objects from the view collection.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Security, Database
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbView

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance sql2016

        Gets all database views

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -Database db1

        Gets the views for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -ExcludeDatabase db1

        Gets the views for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance Server1 -ExcludeSystemView

        Gets the views for all databases that are not system objects (there can be 400+ system views in each DB)

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbView

        Gets the views for the databases on Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance Server1 -ExcludeSystem | Get-DbaDbView

        Pipe the databases from Get-DbaDatabase into Get-DbaDbView

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemView,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $views = $db.views
            if (-not $db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping"
                continue
            }

            if (-not $views) {
                Write-Message -Message "No views exist in the $db database on $instance" -Target $db -Level Verbose
                continue
            }
            if (Test-Bound -ParameterName ExcludeSystemView) {
                $views = $views | Where-Object { -not $_.IsSystemObject }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'CreateDate', 'DateLastModified', 'Name'
            foreach ($view in $views) {

                Add-Member -Force -InputObject $view -MemberType NoteProperty -Name ComputerName -value $view.Parent.ComputerName
                Add-Member -Force -InputObject $view -MemberType NoteProperty -Name InstanceName -value $view.Parent.InstanceName
                Add-Member -Force -InputObject $view -MemberType NoteProperty -Name SqlInstance -value $view.Parent.SqlInstance
                Add-Member -Force -InputObject $view -MemberType NoteProperty -Name Database -value $db.Name

                Select-DefaultView -InputObject $view -Property $defaults
            }
        }
    }
}
