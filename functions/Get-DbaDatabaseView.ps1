function Get-DbaDatabaseView {
    <#
        .SYNOPSIS
            Gets database views for each SqlInstance.

        .DESCRIPTION
            Gets database views for each SqlInstance.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            To get views from specific database(s) - this list is auto populated from the server.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server.

        .PARAMETER ExcludeSystemView
            This switch removes all system objects from the view collection.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: security, Databases
            Author: Klaas Vandenberghe ( @PowerDbaKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Get-DbaDatabaseView -SqlInstance sql2016

            Gets all database views

        .EXAMPLE
            Get-DbaDatabaseView -SqlInstance Server1 -Database db1

            Gets the views for the db1 database

        .EXAMPLE
            Get-DbaDatabaseView -SqlInstance Server1 -ExcludeDatabase db1

            Gets the views for all databases except db1

        .EXAMPLE
            Get-DbaDatabaseView -SqlInstance Server1 -ExcludeSystemView

            Gets the views for all databases that are not system objects (there can be 400+ system views in each DB)

        .EXAMPLE
            'Sql1','Sql2/sqlexpress' | Get-DbaDatabaseView

            Gets the views for the databases on Sql1 and Sql2/sqlexpress

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemView,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                $views = $db.views

                if (!$views) {
                    Write-Message -Message "No views exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }
                if (Test-Bound -ParameterName ExcludeSystemView) {
                    $views = $views | Where-Object { $_.IsSystemObject -eq $false }
                }

                $views | Foreach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name
                }
            }
        }
    }
}