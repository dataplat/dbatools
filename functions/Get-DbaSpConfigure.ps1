function Get-DbaSpConfigure {
    <#
        .SYNOPSIS
            Returns all server level system configuration (sys.configuration/sp_configure) information

        .DESCRIPTION
            This function returns server level system configuration (sys.configuration/sp_configure) information. The information is gathered through SMO Configuration.Properties.
            The data includes the default value for each configuration, for quick identification of values that may have been changed.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a
            collection and receive pipeline input

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            Return only specific configurations.

        .PARAMETER ExcludeName
            Exclude specific configurations.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SpConfig, Configure, Configuration
            Author: Nic Cain, https://sirsql.net/

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaSpConfigure

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance localhost

            Returns server level configuration data on the localhost (ServerName, Name, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue)

        .EXAMPLE
            'localhost','localhost\namedinstance' | Get-DbaSpConfigure

            Returns system configuration information on multiple instances piped into the function

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance sql2012 -Name 'max server memory (MB)'

            Returns only the system configuration for MaxServerMemory on sql2012.

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance sql2012 -ExcludeName 'max server memory (MB)', 'remote access' | Out-GridView

            Returns server level configuration data on sql2012 but excludes for 'max server memory (MB)' and 'remote access'. Values returned in GridView
        #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Config", "ConfigName")]
        [string[]]$Name,
        [string[]]$ExcludeName,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            #Get a list of the configuration Properties. This collection matches entries in sys.configurations
            try {
                $proplist = $server.Configuration.Properties
            }
            catch {
                Stop-Function -Message "Unable to gather configuration properties $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            if ($Name) {
                $proplist = $proplist | Where-Object { $_.DisplayName -in $Name }
            }

            if (Test-Bound "ExcludeName") {
                $proplist = $proplist | Where-Object DisplayName -NotIn $ExcludeName
            }

            #Grab the default sp_configure property values from the external function
            $defaultConfigs = (Get-SqlDefaultSpConfigure -SqlVersion $server.VersionMajor).psobject.properties;

            #Iterate through the properties to get the configuration settings
            foreach ($prop in $proplist) {
                $defaultConfig = $defaultConfigs | Where-Object { $_.Name -eq $prop.DisplayName };

                if ($defaultConfig.Value -eq $prop.RunValue) { $isDefault = $true }
                else { $isDefault = $false }

                #Ignores properties that are not valid on this version of SQL
                if (!([string]::IsNullOrEmpty($prop.RunValue))) {


                    [pscustomobject]@{
                        ServerName            = $server.Name
                        ComputerName          = $server.ComputerName
                        InstanceName          = $server.ServiceName
                        SqlInstance           = $server.DomainInstanceName
                        Name                  = $prop.DisplayName
                        Description           = $prop.Description
                        IsAdvanced            = $prop.IsAdvanced
                        IsDynamic             = $prop.IsDynamic
                        MinValue              = $prop.Minimum
                        MaxValue              = $prop.Maximum
                        ConfiguredValue       = $prop.ConfigValue
                        RunningValue          = $prop.RunValue
                        DefaultValue          = $defaultConfig.Value
                        IsRunningDefaultValue = $isDefault
                        Parent                = $server
                        ConfigName            = $prop.DisplayName
                    } | Select-DefaultView -ExcludeProperty ServerName, Parent, ConfigName
                }
            }
        }
    }
}