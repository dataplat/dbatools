function Get-DbaInstanceProperty {
    <#
    .SYNOPSIS
        Retrieves comprehensive SQL Server instance configuration properties for auditing and comparison

    .DESCRIPTION
        Retrieves all instance-level configuration properties from SQL Server's Information, UserOptions, and Settings collections via SMO. This gives you a complete inventory of server settings like default file paths, memory configuration, security options, and user defaults in a standardized format. Essential for configuration audits, compliance reporting, environment comparisons, and troubleshooting configuration-related issues across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InstanceProperty
        Specifies which SQL Server instance properties to include from Information, UserOptions, and Settings collections. Accepts wildcards and arrays.
        Use this to focus on specific configuration properties like DefaultFile, MaxWorkerThreads, or LoginMode when auditing particular settings across instances.

    .PARAMETER ExcludeInstanceProperty
        Specifies which SQL Server instance properties to exclude from the results. Accepts wildcards and arrays.
        Use this to filter out noisy or irrelevant properties when you need a cleaner view of configuration data for reporting or comparison.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Configure, Configuration, General
        Author: Klaas Vandenberghe (@powerdbaklaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per instance property from the Information, UserOptions, and Settings collections. The function returns properties from three separate SMO collections, outputting each property with contextual information about which collection it came from.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Name: The property name (e.g., DefaultFile, MaxWorkerThreads, LoginMode, TcpPort)
        - Value: The current value of the configuration property (string or mixed type depending on property)
        - PropertyType: The type of property collection - either "Information", "UserOption", or "Setting"

        The -InstanceProperty and -ExcludeInstanceProperty parameters filter which specific properties are returned but do not change the output structure.

    .LINK
        https://dbatools.io/Get-DbaInstanceProperty

    .EXAMPLE
        PS C:\> Get-DbaInstanceProperty -SqlInstance localhost

        Returns SQL Server instance properties on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaInstanceProperty -SqlInstance sql2, sql4\sqlexpress

        Returns SQL Server instance properties on default instance on sql2 and sqlexpress instance on sql4

    .EXAMPLE
        PS C:\> 'sql2','sql4' | Get-DbaInstanceProperty

        Returns SQL Server instance properties on sql2 and sql4

    .EXAMPLE
        PS C:\> Get-DbaInstanceProperty -SqlInstance sql2,sql4 -InstanceProperty DefaultFile

        Returns SQL Server instance property DefaultFile on instance sql2 and sql4

    .EXAMPLE
        PS C:\> Get-DbaInstanceProperty -SqlInstance sql2,sql4 -ExcludeInstanceProperty DefaultFile

        Returns all SQL Server instance properties except DefaultFile on instance sql2 and sql4

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaInstanceProperty -SqlInstance sql2 -SqlCredential $cred

        Connects using sqladmin credential and returns SQL Server instance properties from sql2

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$InstanceProperty,
        [object[]]$ExcludeInstanceProperty,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $infoProperties = $server.Information.Properties

                if ($InstanceProperty) {
                    $infoProperties = $infoProperties | Where-Object Name -In $InstanceProperty
                }
                if ($ExcludeInstanceProperty) {
                    $infoProperties = $infoProperties | Where-Object Name -NotIn $ExcludeInstanceProperty
                }
                foreach ($prop in $infoProperties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Information'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            } catch {
                Stop-Function -Message "Issue gathering information properties for $instance." -Target $instance -ErrorRecord $_ -Continue
            }

            try {
                $userProperties = $server.UserOptions.Properties

                if ($InstanceProperty) {
                    $userProperties = $userProperties | Where-Object Name -In $InstanceProperty
                }
                if ($ExcludeInstanceProperty) {
                    $userProperties = $userProperties | Where-Object Name -NotIn $ExcludeInstanceProperty
                }
                foreach ($prop in $userProperties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'UserOption'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            } catch {
                Stop-Function -Message "Issue gathering user options for $instance." -Target $instance -ErrorRecord $_ -Continue
            }

            try {
                $settingProperties = $server.Settings.Properties

                if ($InstanceProperty) {
                    $settingProperties = $settingProperties | Where-Object Name -In $InstanceProperty
                }
                if ($ExcludeInstanceProperty) {
                    $settingProperties = $settingProperties | Where-Object Name -NotIn $ExcludeInstanceProperty
                }
                foreach ($prop in $settingProperties) {
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name PropertyType -Value 'Setting'
                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
                }
            } catch {
                Stop-Function -Message "Issue gathering settings for $instance." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}