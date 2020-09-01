function Copy-DbaSpConfigure {
    <#
    .SYNOPSIS
        Copy-DbaSpConfigure migrates configuration values from one SQL Server to another.

    .DESCRIPTION
        By default, all configuration values are copied. The -ConfigName parameter is auto-populated for command-line completion and can be used to copy only specific configs.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ConfigName
        Specifies the configuration setting to process. Options for this list are auto-populated from the server. If unspecified, all ConfigNames will be processed.

    .PARAMETER ExcludeConfigName
        Specifies the configuration settings to exclude. Options for this list are auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Configure, SpConfigure
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaSpConfigure

    .EXAMPLE
        PS C:\> Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster

        Copies all sp_configure settings from sqlserver2014a to sqlcluster

    .EXAMPLE
        PS C:\> Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -ConfigName DefaultBackupCompression, IsSqlClrEnabled -SourceSqlCredential $cred

        Copies the values for IsSqlClrEnabled and DefaultBackupCompression from sqlserver2014a to sqlcluster using SQL credentials to authenticate to sqlserver2014a and Windows credentials to authenticate to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -ExcludeConfigName DefaultBackupCompression, IsSqlClrEnabled

        Copies all configs except for IsSqlClrEnabled and DefaultBackupCompression, from sqlserver2014a to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$ConfigName,
        [object[]]$ExcludeConfigName,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $sourceProps = Get-DbaSpConfigure -SqlInstance $sourceServer
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                $destProps = Get-DbaSpConfigure -SqlInstance $destServer
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            foreach ($sourceProp in $sourceProps) {
                $displayName = $sourceProp.DisplayName
                $sConfigName = $sourceProp.ConfigName
                $sConfiguredValue = $sourceProp.ConfiguredValue
                $requiresRestart = $sourceProp.IsDynamic

                $copySpConfigStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $sConfigName
                    Type              = "Configuration Value"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($ConfigName -and $sConfigName -notin $ConfigName -or $sConfigName -in $ExcludeConfigName) {
                    continue
                }

                $destProp = $destProps | Where-Object ConfigName -eq $sConfigName
                if (!$destProp) {
                    Write-Message -Level Verbose -Message "Configuration $sConfigName ('$displayName') does not exist on the destination instance."

                    $copySpConfigStatus.Status = "Skipped"
                    $copySpConfigStatus.Notes = "Configuration does not exist on destination"
                    $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    continue
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Updating $sConfigName [$displayName]")) {
                    try {
                        $destOldConfigValue = $destProp.ConfiguredValue

                        if ($sConfiguredValue -ne $destOldConfigValue) {
                            $result = Set-DbaSpConfigure -SqlInstance $destServer -Name $sConfigName -Value $sConfiguredValue -EnableException -WarningAction SilentlyContinue
                            if ($result) {
                                Write-Message -Level Verbose -Message "Updated $($destProp.ConfigName) ($($destProp.DisplayName)) from $destOldConfigValue to $sConfiguredValue."
                            }
                        }
                        if ($requiresRestart -eq $false) {
                            Write-Message -Level Verbose -Message "Configuration option $sConfigName ($displayName) requires restart."
                            $copySpConfigStatus.Notes = "Requires restart"
                        }
                        $copySpConfigStatus.Status = "Successful"
                        $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        if ($_.Exception -match 'the same as the') {
                            $copySpConfigStatus.Status = "Successful"
                        } else {
                            $copySpConfigStatus.Status = "Failed"
                            $copySpConfigStatus.Notes = (Get-ErrorMessage -Record $_)
                        }
                        $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Could not set $($destProp.ConfigName) to $sConfiguredValue." -Target $sConfigName -ErrorRecord $_
                    }
                }
            }
        }
    }
}