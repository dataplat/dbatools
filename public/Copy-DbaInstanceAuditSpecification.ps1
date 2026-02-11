function Copy-DbaInstanceAuditSpecification {
    <#
    .SYNOPSIS
        Copies server audit specifications from one SQL Server instance to another for compliance standardization.

    .DESCRIPTION
        Migrates server audit specifications between SQL Server instances, allowing DBAs to standardize audit configurations across environments or restore audit settings during disaster recovery. The function scripts existing audit specifications from the source server and recreates them on the destination, but only if the corresponding server audits already exist on the target instance.

        By default, all audit specifications are copied, but you can target specific ones using the -AuditSpecification parameter. Existing specifications on the destination are skipped unless -Force is used to drop and recreate them. This prevents accidental overwrites while enabling intentional updates to audit configurations.

    .PARAMETER Source
        Source SQL Server instance containing the server audit specifications to copy. Requires sysadmin access and SQL Server 2008 or higher.
        The function will read all existing audit specifications from this instance to migrate to the destination.

    .PARAMETER SourceSqlCredential
        Credentials for connecting to the source SQL Server instance to read audit specifications. Use when Windows Authentication is not available.
        Accepts PowerShell credentials (Get-Credential) and supports SQL Server Authentication, Active Directory authentication modes.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server instance where audit specifications will be created. Requires sysadmin access and SQL Server 2008 or higher.
        The corresponding server audits must already exist on this instance before audit specifications can be successfully copied.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance to create audit specifications. Use when Windows Authentication is not available.
        Accepts PowerShell credentials (Get-Credential) and supports SQL Server Authentication, Active Directory authentication modes.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AuditSpecification
        Specifies which server audit specifications to copy by name. Accepts multiple specification names as an array.
        Use this when you need to migrate specific audit specifications rather than all specifications from the source instance.
        If not specified, all audit specifications from the source will be processed.

    .PARAMETER ExcludeAuditSpecification
        Specifies which server audit specifications to skip during the copy operation. Accepts multiple specification names as an array.
        Use this to copy all audit specifications except those you want to exclude, such as environment-specific or test specifications.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Drops and recreates existing audit specifications on the destination instance instead of skipping them.
        Use this when you need to overwrite existing audit specifications with updated configurations from the source.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per audit specification processed with TypeName dbatools.MigrationObject.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: Timestamp when the copy operation was executed (DbaDateTime)
        - SourceServer: Name of the source SQL Server instance
        - DestinationServer: Name of the destination SQL Server instance
        - Name: Name of the audit specification that was copied or processed
        - Type: Always returns "Server Audit Specification"
        - Status: Result of the operation - "Successful", "Skipped", or "Failed"
        - Notes: Additional details about the operation result (e.g., why it was skipped or failure reason)

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
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
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
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
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

                $copyAuditSpecStatus = [PSCustomObject]@{
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
                        if ($Pscmdlet.ShouldProcess($destinstance, "Server audit $auditSpecName exists at destination. Use -Force to drop and migrate.")) {
                            Write-Message -Level Verbose -Message "Server audit $auditSpecName exists at destination. Use -Force to drop and migrate."
                            $copyAuditSpecStatus.Status = "Skipped"
                            $copyAuditSpecStatus.Notes = "Already exists on destination"
                            $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
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
                                Write-Message -Level Verbose -Message "Issue dropping audit specification $auditSpecName on $destinstance | $PSItem"
                                continue
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
                        Write-Message -Level Verbose -Message "Issue creating audit specification $auditSpecName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}