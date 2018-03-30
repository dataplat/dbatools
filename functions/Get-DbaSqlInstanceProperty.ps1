#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaSqlInstanceProperty {
    <#
        .SYNOPSIS
            Gets SQL Instance properties of one or more instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaSqlInstanceProperty command gets SQL Instance properties from the SMO object sqlserver.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Klaas Vandenberghe (@powerdbaklaas)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

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

        .EXAMPLE
            $cred = Get-Credential sqladmin
            Get-DbaSqlInstanceProperty -SqlInstance sql2 -SqlCredential $cred

            Connects using sqladmin credential and returns SQL Instance properties from sql2
#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                foreach ($prop in $server.Information.Properties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Information'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            }
            catch {
                Stop-Function -Message "Issue gathering information properties for $instance." -Target $instance -ErrorRecord $_ -Continue
            }

            try {
                foreach ($prop in $server.Useroptions.Properties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'UserOption'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            }
            catch {
                Stop-Function -Message "Issue gathering user options for $instance." -Target $instance -ErrorRecord $_ -Continue
            }

            try {
                foreach ($prop in $server.Settings.Properties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Setting'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            }
            catch {
                Stop-Function -Message "Issue gathering settings for $instance." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}