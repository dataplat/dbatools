function Copy-DbaInstanceAudit {
    <#
    .SYNOPSIS
        Copies SQL Server audit objects from source to destination instances

    .DESCRIPTION
        Migrates SQL Server audit objects and their configurations from one instance to another, preserving audit settings and file paths. This function handles the complex task of recreating audit definitions on destination servers, making it essential for server migrations, disaster recovery scenarios, or standardizing auditing policies across multiple SQL Server instances. By default, all audits are copied, but you can specify individual audits to migrate. If an audit already exists on the destination, it will be skipped unless -Force is used to drop and recreate it.

    .PARAMETER Source
        Source SQL Server instance containing the audit objects to copy. Requires sysadmin access to read audit configurations and their associated file paths.
        Must be SQL Server 2008 or higher since server audits were introduced in SQL Server 2008.

    .PARAMETER SourceSqlCredential
        Login credentials for the source SQL Server instance. Use this when the current Windows user doesn't have sysadmin access to read audit objects.
        Must have sysadmin privileges since audit configurations require elevated permissions to access.

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server instance where audit objects will be created. Requires sysadmin access to create audits and potentially create audit file directories.
        Must be SQL Server 2008 or higher since server audits were introduced in SQL Server 2008.

    .PARAMETER DestinationSqlCredential
        Login credentials for the destination SQL Server instance. Use this when the current Windows user doesn't have sysadmin access to create audit objects.
        Must have sysadmin privileges since creating audits and directories requires elevated permissions.

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Audit
        Specifies which server audits to copy by name. Use this when you only need to migrate specific audits rather than all audits on the server.
        Supports tab completion with audit names from the source server. If not specified, all audits will be copied.

    .PARAMETER ExcludeAudit
        Specifies server audits to skip during the copy operation. Use this when you want to copy most audits but exclude specific ones that shouldn't be migrated.
        Supports tab completion with audit names from the source server. Cannot be used with the -Audit parameter.

    .PARAMETER Path
        Specifies the directory path where audit files will be created on the destination server. Use this when the original audit file path from the source doesn't exist on the destination.
        If not specified, the function attempts to use the source audit's original file path, or falls back to the default data directory if the path doesn't exist.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Drops and recreates audits that already exist on the destination server. Also creates missing audit file directories if they don't exist.
        Without this switch, existing audits are skipped and missing directories cause the operation to fail.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaInstanceAudit

    .OUTPUTS
        PSCustomObject

        Returns one object per audit copied or encountered (regardless of success or failure status). The object represents the result of the copy operation for a single audit.

        Default display properties (via Select-DefaultView):
        - DateTime: The timestamp when the copy operation was attempted
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the server audit being copied
        - Type: Always "Server Audit" indicating the type of object being copied
        - Status: The result status of the copy operation (Successful, Skipped, or Failed)
        - Notes: Additional information about the copy operation (reason for skip, error details, etc.)

        The object type is set to "MigrationObject" for proper display formatting. All properties are always available using Select-Object *.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster

        Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster -Audit tg_noDbDrop -SourceSqlCredential $cred -Force

        Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceAudit -Source sqlserver-0 -Destination sqlserver-1 -Audit audit1 -Path 'C:\audit1'

        Copies audit audit1 from sqlserver-0 to sqlserver-1. The file path on sqlserver-1 will be set to 'C:\audit1'.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Audit,
        [object[]]$ExcludeAudit,
        [string]$Path,
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
        $serverAudits = $sourceServer.Audits

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
            $destAudits = $destServer.Audits
            foreach ($currentAudit in $serverAudits) {
                $auditName = $currentAudit.Name

                $copyAuditStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $auditName
                    Type              = "Server Audit"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Audit -and $auditName -notin $Audit -or $auditName -in $ExcludeAudit) {
                    continue
                }

                if ($Path) {
                    $currentAudit.FilePath = $Path
                }

                if ($destAudits.Name -contains $auditName) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Server audit $auditName exists at destination. Use -Force to drop and migrate.")) {
                            $copyAuditStatus.Status = "Skipped"
                            $copyAuditStatus.Notes = "Already exists on destination"
                            Write-Message -Level Verbose -Message "Server audit $auditName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server audit $auditName")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server audit $auditName."
                                foreach ($spec in $destServer.ServerAuditSpecifications) {
                                    if ($auditSpecification.Auditname -eq $auditName) {
                                        $auditSpecification.Drop()
                                    }
                                }

                                $destServer.audits[$auditName].Disable()
                                $destServer.audits[$auditName].Alter()
                                $destServer.audits[$auditName].Drop()
                            } catch {
                                $copyAuditStatus.Status = "Failed"
                                $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping audit from $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if (-not [string]::IsNullOrEmpty($currentAudit.Filepath) -and -not (Test-DbaPath -SqlInstance $destServer -Path $currentAudit.Filepath)) {
                    if ($Force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory.")) {
                            $copyAuditStatus.Status = "Skipped"
                            $copyAuditStatus.Notes = "$($currentAudit.Filepath) does not exist on $destinstance. Skipping $auditName. Specify -Force to create the directory."
                            $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        Write-Message -Level Verbose -Message "Force specified. Creating directory."

                        $resolvedComputerName = Resolve-DbaComputerName -ComputerName $destServer
                        $root = $currentAudit.Filepath.Substring(0, 3)
                        $rootUnc = Join-AdminUnc $resolvedComputerName $root

                        if ((Test-Path $rootUnc) -eq $true ) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Creating directory $($currentAudit.Filepath)")) {
                                try {
                                    $null = New-DbaDirectory -SqlInstance $destServer -Path $currentAudit.Filepath -EnableException
                                } catch {
                                    Write-Message -Level Warning -Message "Couldn't create directory $($currentAudit.Filepath). Using default data directory."
                                    $datadir = Get-SqlDefaultPaths $destServer data
                                    $currentAudit.FilePath = $datadir
                                }
                            }
                        } else {
                            $datadir = Get-SqlDefaultPaths $destServer data
                            $currentAudit.FilePath = $datadir
                        }
                    }
                }
                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server audit $auditName")) {
                    try {
                        Write-Message -Level Verbose -Message "File path $($currentAudit.Filepath) exists on $destinstance."
                        Write-Message -Level Verbose -Message "Copying server audit $auditName."
                        $sql = $currentAudit.Script() | Out-String
                        $destServer.Query($sql)
                        $copyAuditStatus.Status = "Successful"
                        $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAuditStatus.Status = "Failed"
                        $copyAuditStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating audit on $destinstance | $PSItem"
                    }
                }
            }
        }
    }
}