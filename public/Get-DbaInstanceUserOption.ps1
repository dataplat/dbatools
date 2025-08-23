function Get-DbaInstanceUserOption {
    <#
    .SYNOPSIS
        Retrieves instance-level user option defaults that affect new database connections

    .DESCRIPTION
        Returns the default user options configured at the SQL Server instance level that are automatically applied to new database connections. These settings include ANSI compliance options like ANSI_NULLS, QUOTED_IDENTIFIER, date format preferences, and other connection-level defaults. This is useful when standardizing connection behavior across environments or troubleshooting why applications behave differently on different instances. Unlike Get-DbaDbccUserOption which shows current session settings, this command shows the instance defaults that would be inherited by new connections.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.
        This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Configure, UserOption, General
        Author: Klaas Vandenberghe (@powerdbaklaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceUserOption

    .EXAMPLE
        PS C:\> Get-DbaInstanceUserOption -SqlInstance localhost

        Returns SQL Instance user options on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaInstanceUserOption -SqlInstance sql2, sql4\sqlexpress

        Returns SQL Instance user options on default instance on sql2 and sqlexpress instance on sql4

    .EXAMPLE
        PS C:\> 'sql2','sql4' | Get-DbaInstanceUserOption

        Returns SQL Instance user options on sql2 and sql4

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $props = $server.useroptions.properties
            foreach ($prop in $props) {
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value
            }
        }
    }
}