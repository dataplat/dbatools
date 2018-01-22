function Copy-DbaServerAudit {
    <#
        .SYNOPSIS
            Copy-DbaServerAudit migrates server audits from one SQL Server to another.

        .DESCRIPTION
            By default, all audits are copied. The -Audit parameter is auto-populated for command-line completion and can be used to copy only specific audits.

            If the audit already exists on the destination, it will be skipped unless -Force is used.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Audit
            The audit(s) to process. Options for this list are auto-populated from the server. If unspecified, all audits will be processed.

        .PARAMETER ExcludeAudit
            The audit(s) to exclude. Options for this list are auto-populated from the server.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER Force
            If this switch is enabled, the audits will be dropped and recreated on Destination.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaServerAudit

        .EXAMPLE
            Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster

            Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster -Audit tg_noDbDrop -SourceSqlCredential $cred -Force

            Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        .EXAMPLE
            Copy-DbaServerAudit -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

            Shows what would happen if the command were executed using force.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Audit,
        [object[]]$ExcludeAudit,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
            Stop-Function -Message "Server Audits are only supported in SQL Server 2008 and above. Quitting."
            return
        }

        $serverAudits = $sourceServer.Audits
        $destAudits = $destServer.Audits
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($currentAudit in $serverAudits) {
            $auditName = $currentAudit.Name

            $copyAuditStatus = [pscustomobject]@{
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

            $sql = $currentAudit.Script() | Out-String

            if ($destAudits.Name -contains $auditName) {
                if ($force -eq $false) {
                    $copyAuditStatus.Status = "Skipped"
                    $copyAuditStatus.Notes = "Already exists"
                    Write-Message -Level Verbose -Message "Server audit $auditName exists at destination. Use -Force to drop and migrate."
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditName")) {
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
                        }
                        catch {
                            $copyAuditStatus.Status = "Failed"
                            $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping audit from destination." -Target $auditName -ErrorRecord $_
                        }
                    }
                }
            }

            if ($null -ne ($currentAudit.Filepath) -AND (Test-DbaSqlPath -SqlInstance $destServer -Path $currentAudit.Filepath) -eq $false) {
                if ($Force -eq $false) {
                    Write-Message -Level Verbose -Message "$($currentAudit.Filepath) does not exist on $destination. Skipping $auditName. Specify -Force to create the directory."

                    $copyAuditStatus.Status = "Skipped"
                    $copyAuditStatus.Notes = "Already exists"
                    $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    continue
                }
                else {
                    Write-Message -Level Verbose -Message "Force specified. Creating directory."

                    $destNetBios = Resolve-NetBiosName $destServer
                    $path = Join-AdminUnc $destNetBios $currentAudit.Filepath
                    $root = $currentAudit.Filepath.Substring(0, 3)
                    $rootUnc = Join-AdminUnc $destNetBios $root

                    if ((Test-Path $rootUnc) -eq $true) {
                        try {
                            if ($Pscmdlet.ShouldProcess($destination, "Creating directory $($currentAudit.Filepath)")) {
                                $null = New-Item -ItemType Directory $currentAudit.Filepath -ErrorAction Continue
                            }
                        }
                        catch {
                            Write-Message -Level Verbose -Message "Couldn't create directory $($currentAudit.Filepath). Using default data directory."
                            $datadir = Get-SqlDefaultPaths $destServer data
                            $sql = $sql.Replace($currentAudit.FilePath, $datadir)
                        }
                    }
                    else {
                        $datadir = Get-SqlDefaultPaths $destServer data
                        $sql = $sql.Replace($currentAudit.FilePath, $datadir)
                    }
                }
            }
            if ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditName")) {
                try {
                    Write-Message -Level Verbose -Message "File path $($currentAudit.Filepath) exists on $Destination."
                    Write-Message -Level Verbose -Message "Copying server audit $auditName."
                    $destServer.Query($sql)

                    $copyAuditStatus.Status = "Successful"
                    $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copyAuditStatus.Status = "Failed"
                    $copyAuditStatus.Notes = $_.Exception
                    $copyAuditStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue creating audit." -Target $auditName -ErrorRecord $_
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlAudit
    }
}