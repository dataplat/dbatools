function Get-DbaDatabaseAssembly {
    <#
.SYNOPSIS
Gets SQL Database Assembly information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaDatabaseAssembly command gets SQL Database Assembly information for each instance(s) of SQL Server.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
SqlCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaDatabaseAssembly

.EXAMPLE
Get-DbaDatabaseAssembly -SqlInstance localhost
Returns all Database Assembly on the local default SQL Server instance

.EXAMPLE
Get-DbaDatabaseAssembly -SqlInstance localhost, sql2016
Returns all Database Assembly for the local and sql2016 SQL Server instances

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    PROCESS {
        foreach ($instance in $SqlInstance) {
            Write-Verbose "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }



            foreach ($database in ($server.Databases | Where-Object IsAccessible)) {
                try {
                    foreach ($assembly in $database.assemblies) {

                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name ComputerName -value $assembly.Parent.Parent.NetName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name InstanceName -value $assembly.Parent.Parent.ServiceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name SqlInstance -value $assembly.Parent.Parent.DomainInstanceName

                        Select-DefaultView -InputObject $assembly -Property ComputerName, InstanceName, SqlInstance, ID, Name, Owner, 'AssemblySecurityLevel as SecurityLevel', CreateDate, IsSystemObject, Version

                    }
                }
                catch {
                    Write-Warning $_
                }
            }
        }
    }
}
