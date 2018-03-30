function Copy-DbaServerAuditSpecification {
    <#
        .SYNOPSIS
            Copy-DbaServerAuditSpecification migrates server audit specifications from one SQL Server to another.

        .DESCRIPTION
            By default, all audits are copied. The -AuditSpecification parameter is auto-populated for command-line completion and can be used to copy only specific audits.

            If the audit specification already exists on the destination, it will be skipped unless -Force is used.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Copy-DbaServerAuditSpecification

        .EXAMPLE
            Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster

            Copies all server audits from sqlserver2014a to sqlcluster using Windows credentials to connect. If audits with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster -ServerAuditSpecification tg_noDbDrop -SourceSqlCredential $cred -Force

            Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster using SQL credentials to connect to sqlserver2014a and Windows credentials to connect to sqlcluster. If an audit specification with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        .EXAMPLE
            Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

            Shows what would happen if the command were executed using force.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$AuditSpecification,
        [object[]]$ExcludeAuditSpecification,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }

        if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $destination. Quitting."
            return
        }

        if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
            Stop-Function -Message "Server Audit Specifications are only supported in SQL Server 2008 and above. Quitting."
            return
        }

        if ($destServer.VersionMajor -lt $sourceServer.VersionMajor) {
            Stop-Function -Message "Migration from version $($destServer.VersionMajor) to version $($sourceServer.VersionMajor) is not supported."
            return
        }

        $AuditSpecifications = $sourceServer.ServerAuditSpecifications
        $destAudits = $destServer.ServerAuditSpecifications
    }
    process {
        if (Test-FunctionInterrupt) { return }

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
                $copyAuditSpecStatus.Status = "Skipped"
                $copyAuditSpecStatus.Notes = "Already exists"
                Write-Message -Level Warning -Message "Audit $($auditSpec.AuditName) does not exist on $Destination. Skipping $auditSpecName."
                continue
            }

            if ($destAudits.name -contains $auditSpecName) {
                if ($force -eq $false) {
                    Write-Message -Level Verbose -Message "Server audit $auditSpecName exists at destination. Use -Force to drop and migrate."

                    $copyAuditSpecStatus.Status = "Skipped"
                    $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditSpecName and recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping server audit $auditSpecName"
                            $destServer.ServerAuditSpecifications[$auditSpecName].Drop()
                        }
                        catch {
                            $copyAuditSpecStatus.Status = "Failed"
                            $copyAuditSpecStatus.Notes = $_.Exception
                            $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping audit spec" -Target $auditSpecName -ErrorRecord $_ -Continue
                        }
                    }
                }
            }
            if ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditSpecName")) {
                try {
                    Write-Message -Level Verbose -Message "Copying server audit $auditSpecName"
                    $sql = $auditSpec.Script() | Out-String
                    Write-Message -Level Debug -Message $sql
                    $destServer.Query($sql)

                    $copyAuditSpecStatus.Status = "Successful"
                    $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copyAuditSpecStatus.Status = "Failed"
                    $copyAuditSpecStatus.Notes = $_.Exception
                    $copyAuditSpecStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue creating audit spec on destination" -Target $auditSpecName -ErrorRecord $_
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlAuditSpecification
    }
}
