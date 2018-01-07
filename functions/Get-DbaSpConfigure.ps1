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
            PSCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER ConfigName
            Return only specific configurations -- auto-populated from source server

        .NOTES
            Author: Nic Cain, https://sirsql.net/

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaSpConfigure

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance localhost

            Returns server level configuration data on the localhost (ServerName, ConfigName, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue)

        .EXAMPLE
            'localhost','localhost\namedinstance' | Get-DbaSpConfigure

            Returns system configuration information on multiple instances piped into the function

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance localhost

            Returns server level configuration data on the localhost (ServerName, ConfigName, DisplayName, Description, IsAdvanced, IsDynamic, MinValue, MaxValue, ConfiguredValue, RunningValue, DefaultValue, IsRunningDefaultValue)

        .EXAMPLE
            Get-DbaSpConfigure -SqlInstance sql2012 -ConfigName MaxServerMemory

            Returns only the system configuration for MaxServerMemory. Configs is auto-populated for tabbing convenience.
        #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Config")]
        [object[]]$ConfigName
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Warning "Failed to connect to: $instance"
                continue
            }

            #Get a list of the configuration property parents, and exclude the Parent, Properties values
            $proplist = Get-Member -InputObject $server.Configuration -MemberType Property -Force | Select-Object Name | Where-Object { $_.Name -ne "Parent" -and $_.Name -ne "Properties" }

            if ($ConfigName) {
                $proplist = $proplist | Where-Object { $_.Name -in $ConfigName }
            }

            #Grab the default sp_configure property values from the external function
            $defaultConfigs = (Get-SqlDefaultSpConfigure -SqlVersion $server.VersionMajor).psobject.properties;

            #Iterate through the properties to get the configuration settings
            foreach ($prop in $proplist) {
                $propInfo = $server.Configuration.$($prop.Name)
                $defaultConfig = $defaultConfigs | Where-Object { $_.Name -eq $propInfo.DisplayName };

                if ($defaultConfig.Value -eq $propInfo.RunValue) { $isDefault = $true }
                else { $isDefault = $false }

                #Ignores properties that are not valid on this version of SQL
                if (!([string]::IsNullOrEmpty($propInfo.RunValue))) {
                    # some displaynames were empty
                    $displayname = $propInfo.DisplayName
                    if ($displayname.Length -eq 0) { $displayname = $prop.Name }

                    [pscustomobject]@{
                        ServerName            = $server.Name
                        ConfigName            = $prop.Name
                        DisplayName           = $displayname
                        Description           = $propInfo.Description
                        IsAdvanced            = $propInfo.IsAdvanced
                        IsDynamic             = $propInfo.IsDynamic
                        MinValue              = $propInfo.Minimum
                        MaxValue              = $propInfo.Maximum
                        ConfiguredValue       = $propInfo.ConfigValue
                        RunningValue          = $propInfo.RunValue
                        DefaultValue          = $defaultConfig.Value
                        IsRunningDefaultValue = $isDefault
                    }
                }
            }
        }
    }
}
