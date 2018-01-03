function Get-DbaJobCategory {
    <#
.SYNOPSIS
Gets SQL Agent Job Category information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaJobCategory returns connected SMO object for SQL Agent Job Category information for each instance(s) of SQL Server.

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

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaJobCategory

.EXAMPLE
Get-DbaJobCategory -SqlInstance localhost
Returns all SQL Agent Job Categories on the local default SQL Server instance

.EXAMPLE
Get-DbaJobCategory -SqlInstance localhost, sql2016
Returns all SQL Agent Job Categories for the local and sql2016 SQL Server instances

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
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

            foreach ($jobCategory in $server.JobServer.JobCategories) {
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name ComputerName -value $jobCategory.Parent.Parent.NetName
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name InstanceName -value $jobCategory.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name SqlInstance -value $jobCategory.Parent.Parent.DomainInstanceName

                Select-DefaultView -InputObject $jobCategory -Property ComputerName, InstanceName, SqlInstance, ID, Name, CategoryType
            }
        }
    }
}