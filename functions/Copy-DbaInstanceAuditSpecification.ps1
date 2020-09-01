function Copy-DbaInstanceAuditSpecification {
    <#
    .SYNOPSIS
        Copy-DbaInstanceAuditSpecification migrates server audit specifications from one SQL Server to another.

    .DESCRIPTION
        By default, all audits are copied. The -AuditSpecification parameter is auto-populated for command-line completion and can be used to copy only specific audits.

        If the audit specification already exists on the destination, it will be skipped unless -Force is used.

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

    .PARAMETER AuditSpecification
        The Server Audit Specification(s) to process. Options for this list are auto-populated from the server. If unspecified, all Server Audit Specifications will be processed.

    .PARAMETER ExcludeAuditSpecification
        The Server Audit Specification(s) to exclude. Options for this list are auto-populated from the server

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Audits Specifications will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration,ServerAudit,AuditSpecification
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaInstanceAuditSpecification

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAuditSpecification -Source sqlserver2014a -Destination sqlcluster

        Copies all server audits from sqlserver2014a to sqlcluster using Windows credentials to connect. If audits with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAuditSpecification -Source sqlserver2014a -Destination sqlcluster -AuditSpecification tg_noDbDrop -SourceSqlCredential $cred -Force

        Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster using SQL credentials to connect to sqlserver2014a and Windows credentials to connect to sqlcluster. If an audit specification with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAuditSpecification -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$AuditSpecification,
        [object[]]$ExcludeAuditSpecification,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }

        $AuditSpecifications = $sourceServer.ServerAuditSpecifications

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance. Quitting."
                return
            }

            if ($destServer.VersionMajor -lt $sourceServer.VersionMajor) {
                Stop-Function -Message "Migration from version $($destServer.VersionMajor) to version $($sourceServer.VersionMajor) is not supported."
                return
            }
            $destAudits = $destServer.ServerAuditSpecifications
            foreach ($auditSpec in $AuditSpecifications) {
                $auditSpecName = $auditSpec.Name

                $copyAuditSpecStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Server Audit Specification"
                    Name              = $auditSpecName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($AuditSpecification -and $auditSpecName -notin $AuditSpecification -or $auditSpecName -in $ExcludeAuditSpecification) {
                    continue
                }

                $destServer.Audits.Refresh()
                if ($destServer.Audits.Name -notcontains $auditSpec.AuditName) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Audit $($auditSpec.AuditName) does not exist on $destinstance. Skipping $auditSpecName.")) {
                        $copyAuditSpecStatus.Status = "Skipped"
                        $copyAuditSpecStatus.Notes = "Audit $($auditSpec.AuditName) does not exist on $destinstance. Skipping $auditSpecName."
                        Write-Message -Level Warning -Message "Audit $($auditSpec.AuditName) does not exist on $destinstance. Skipping $auditSpecName."
                        $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($destAudits.name -contains $auditSpecName) {
                    if ($force -eq $false) {
                        Write-Message -Level Verbose -Message "Server audit $auditSpecName exists at destination. Use -Force to drop and migrate."

                        $copyAuditSpecStatus.Status = "Skipped"
                        $copyAuditSpecStatus.Notes = "Already exists on destination"
                        $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server audit $auditSpecName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server audit $auditSpecName"
                                $destServer.ServerAuditSpecifications[$auditSpecName].Drop()
                            } catch {
                                $copyAuditSpecStatus.Status = "Failed"
                                $copyAuditSpecStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue dropping audit spec" -Target $auditSpecName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server audit $auditSpecName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying server audit $auditSpecName"
                        $sql = $auditSpec.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)

                        $copyAuditSpecStatus.Status = "Successful"
                        $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAuditSpecStatus.Status = "Failed"
                        $copyAuditSpecStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue creating audit spec on destination" -Target $auditSpecName -ErrorRecord $_
                    }
                }
            }
        }
    }
}