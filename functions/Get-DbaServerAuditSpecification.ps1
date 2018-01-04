function Get-DbaServerAuditSpecification {
    <#
.SYNOPSIS
Gets SQL Security Audit Specification information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaServerAuditSpecification command gets SQL Security Audit Specification information for each instance(s) of SQL Server.

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
https://dbatools.io/Get-DbaServerAuditSpecification

.EXAMPLE
Get-DbaServerAuditSpecification -SqlInstance localhost
Returns all Security Audit Specifications on the local default SQL Server instance

.EXAMPLE
Get-DbaServerAuditSpecification -SqlInstance localhost, sql2016
Returns all Security Audit Specifications for the local and sql2016 SQL Server instances

#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Verbose "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.versionMajor -lt 10) {
                Write-Warning "Server Audits are only supported in SQL Server 2008 and above. Quitting."
                continue
            }

            foreach ($auditSpecification in $server.ServerAuditSpecifications) {
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $auditSpecification -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                Select-DefaultView -InputObject $auditSpecification -Property ComputerName, InstanceName, SqlInstance, ID, Name, AuditName, Enabled, CreateDate, DateLastModified, Guid
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-SqlServerAuditSpecification
    }
}
