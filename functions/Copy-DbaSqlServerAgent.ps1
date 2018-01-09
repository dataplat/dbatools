function Copy-DbaSqlServerAgent {
    <#
        .SYNOPSIS
            Copy SQL Server Agent from one server to another.

        .DESCRIPTION
            A wrapper function that calls the associated Copy command for each of the object types seen in SSMS under SQL Server Agent. This also copies all of the the SQL Agent properties (job history max rows, DBMail profile name, etc.).

            You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

        .PARAMETER DisableJobsOnDestination
            If this switch is enabled, the jobs will be disabled on Destination after copying.

        .PARAMETER DisableJobsOnSource
            If this switch is enabled, the jobs will be disabled on Source after copying.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER Force
            If this switch is enabled, existing objects on Destination with matching names from Source will be dropped, then copied.

        .NOTES
            Tags: Migration, SqlServerAgent, SqlAgent
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaSqlServerAgent

        .EXAMPLE
            Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster

            Copies all job server objects from sqlserver2014a to sqlcluster using Windows credentials for authentication. If job objects with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

            Copies all job objects from sqlserver2014a to sqlcluster using SQL credentials to authentication to sqlserver2014a and Windows credentials to authenticate to sqlcluster.

        .EXAMPLE
            Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster -WhatIf

            Shows what would happen if the command were executed.
    #>
    [cmdletbinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Switch]$DisableJobsOnDestination,
        [Switch]$DisableJobsOnSource,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        Invoke-SmoCheck -SqlInstance $sourceServer
        Invoke-SmoCheck -SqlInstance $destServer

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        $sourceAgent = $sourceServer.JobServer
    }
    process {

        # All of these support whatif inside of them
        Copy-DbaAgentCategory -Source $sourceServer -Destination $destServer -Force:$force
        Copy-DbaAgentOperator -Source $sourceServer -Destination $destServer -Force:$force
        Copy-DbaAgentAlert -Source $sourceServer -Destination $destServer -Force:$force -IncludeDefaults
        Copy-DbaAgentProxyAccount -Source $sourceServer -Destination $destServer -Force:$force
        Copy-DbaAgentSharedSchedule -Source $sourceServer -Destination $destServer -Force:$force
        Copy-DbaAgentJob -Source $sourceServer -Destination $destServer -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource

        # To do
        <#
            Copy-DbaAgentMasterServer -Source $sourceServer -Destination $destServer -Force:$force
            Copy-DbaAgentTargetServer -Source $sourceServer -Destination $destServer -Force:$force
            Copy-DbaAgentTargetServerGroup -Source $sourceServer -Destination $destServer -Force:$force
        #>

        <# Here are the properties which must be migrated separately #>
        $copyAgentPropStatus = [pscustomobject]@{
            SourceServer      = $sourceServer.Name
            DestinationServer = $destServer.Name
            Name              = "Server level properties"
            Type              = "Agent Properties"
            Status            = $null
            Notes             = $null
            DateTime          = [DbaDateTime](Get-Date)
        }

        if ($Pscmdlet.ShouldProcess($destination, "Copying Agent Properties")) {
            try {
                Write-Message -Level Verbose -Message "Copying SQL Agent Properties"
                $sql = $sourceAgent.Script() | Out-String
                $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                $sql = $sql -replace [Regex]::Escape("@errorlog_file="), [Regex]::Escape("--@errorlog_file=")
                $sql = $sql -replace [Regex]::Escape("@auto_start="), [Regex]::Escape("--@auto_start=")
                Write-Message -Level Debug -Message $sql
                $null = $destServer.Query($sql)

                $copyAgentPropStatus.Status = "Successful"
                $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
            catch {
                $copyAgentPropStatus.Status = "Failed"
                $copyAgentPropStatus.Notes = $_.Exception.Message
                $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                Stop-Function -Message "Issue copying agent properties. This happens sometimes, moving on." -Target $destination
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlServerAgent
    }
}