function Get-DbaSqlInstanceProperty {
    <#
.SYNOPSIS
Gets SQL Instance properties of one or more instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaSqlInstanceProperty command gets SQL Instance properties from the SMO object sqlserver.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Klaas Vandenberghe (@powerdbaklaas)
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaSqlInstanceProperty

.EXAMPLE
Get-DbaSqlInstanceProperty -SqlInstance localhost
Returns SQL Instance properties on the local default SQL Server instance

.EXAMPLE
Get-DbaSqlInstanceProperty -SqlInstance sql2, sql4\sqlexpress
Returns SQL Instance properties on default instance on sql2 and sqlexpress instance on sql4

.EXAMPLE
'sql2','sql4' | Get-DbaSqlInstanceProperty
Returns SQL Instance properties on sql2 and sql4

#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            try {
                $props = $server.information.properties
                foreach ($prop in $props) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Information'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            }
            catch { } # SMO bug sometimes complains w/e
            $props = $server.useroptions.properties
            foreach ($prop in $props) {
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'UserOption'
                Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
            }
            $props = $server.settings.properties
            foreach ($prop in $props) {
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Setting'
                Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
            }
        }
    }
}