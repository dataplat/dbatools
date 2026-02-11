function Copy-DbaSpConfigure {
    <#
    .SYNOPSIS
        Copies SQL Server configuration settings (sp_configure values) from source to destination instances.

    .DESCRIPTION
        This function retrieves all sp_configure settings from the source SQL Server and applies them to one or more destination instances, ensuring consistent configuration across your environment. Only settings that differ between source and destination are updated, making it safe for standardizing existing servers. The function automatically handles settings that require a restart and provides detailed reporting of which configurations were changed, skipped, or failed. Use this when building new servers to match production standards, migrating instances, or ensuring consistent configuration across development and testing environments.

    .PARAMETER Source
        The source SQL Server instance from which sp_configure settings will be copied. Must have sysadmin access to read configuration values.
        Use this as your template server when standardizing configurations across multiple instances or when setting up new servers to match production standards.

    .PARAMETER SourceSqlCredential
        Credentials for connecting to the source SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Use this when the source server requires different authentication than your current Windows session, such as SQL Server authentication or domain service accounts.

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        One or more destination SQL Server instances where sp_configure settings will be applied. Must have sysadmin access to modify configuration values.
        Accepts multiple instances for bulk configuration updates across your environment.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instances. Accepts PowerShell credentials (Get-Credential).
        Use this when destination servers require different authentication than your current Windows session, such as SQL Server authentication or domain service accounts.

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ConfigName
        Specifies which sp_configure settings to copy from source to destination. Accepts one or more configuration names such as 'max server memory (MB)' or 'backup compression default'.
        Use this when you need to update only specific settings rather than copying all configurations, particularly useful for targeted changes like memory settings or backup options.

    .PARAMETER ExcludeConfigName
        Specifies which sp_configure settings to skip during the copy operation. Accepts one or more configuration names to exclude from processing.
        Use this when copying most settings but need to preserve specific destination values, such as excluding 'max server memory (MB)' when servers have different hardware specifications.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per sp_configure setting processed with TypeName dbatools.MigrationObject, regardless of whether the setting was updated, skipped, or failed.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: Timestamp when the operation was performed (DbaDateTime object)
        - SourceServer: Name of the source SQL Server instance
        - DestinationServer: Name of the destination SQL Server instance
        - Name: The name of the sp_configure setting that was copied
        - Type: Always "Configuration Value"
        - Status: The result of the operation - either "Skipped", "Successful", or "Failed"
        - Notes: Additional details about the operation (e.g., "Configuration does not exist on destination", "Requires restart", or error message if failed)

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
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $sourceProps = Get-DbaSpConfigure -SqlInstance $sourceServer
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
                $destProps = Get-DbaSpConfigure -SqlInstance $destServer
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            foreach ($sourceProp in $sourceProps) {
                $displayName = $sourceProp.DisplayName
                $sConfigName = $sourceProp.ConfigName
                $sConfiguredValue = $sourceProp.ConfiguredValue
                $requiresRestart = $sourceProp.IsDynamic

                $copySpConfigStatus = [PSCustomObject]@{
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
                    if ($Pscmdlet.ShouldProcess($destinstance, "Skipping $sConfigName ('$displayName') because it does not exist on the destination instance")) {
                        Write-Message -Level Verbose -Message "Configuration $sConfigName ('$displayName') does not exist on the destination instance."
                        $copySpConfigStatus.Status = "Skipped"
                        $copySpConfigStatus.Notes = "Configuration does not exist on destination"
                        $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                $destOldConfigValue = $destProp.ConfiguredValue

                if ($sConfiguredValue -ne $destOldConfigValue) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating $sConfigName [$displayName] from $destOldConfigValue to $sConfiguredValue")) {
                        try {
                            $result = Set-DbaSpConfigure -SqlInstance $destServer -Name $sConfigName -Value $sConfiguredValue -EnableException -WarningAction SilentlyContinue
                            if ($result) {
                                Write-Message -Level Verbose -Message "Updated $($destProp.ConfigName) ($($destProp.DisplayName)) from $destOldConfigValue to $sConfiguredValue."
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
                                $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            } else {
                                $copySpConfigStatus.Status = "Failed"
                                $copySpConfigStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue updating $sConfigName [$displayName] from $destOldConfigValue to $sConfiguredValue on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }
            }
        }
    }
}