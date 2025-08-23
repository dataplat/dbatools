function Copy-DbaEndpoint {
    <#
    .SYNOPSIS
        Copies SQL Server endpoints from source instance to destination instances for migration scenarios.

    .DESCRIPTION
        Migrates user-defined endpoints (excluding system endpoints) from a source SQL Server to one or more destination servers. This includes Service Broker, Database Mirroring, and Availability Group endpoints that are essential for high availability configurations.

        Existing endpoints on the destination are skipped by default to prevent conflicts, but can be overwritten using the -Force parameter. The function scripts the complete endpoint definition from the source and recreates it on each destination server.

    .PARAMETER Source
        Specifies the source SQL Server instance containing endpoints to copy. Must have sysadmin access to enumerate and script endpoint definitions.
        Use this to identify the server containing Service Broker, Database Mirroring, or Availability Group endpoints needed on other instances.

    .PARAMETER SourceSqlCredential
        Specifies alternative credentials for connecting to the source SQL Server instance. Required when Windows Authentication is not available or sufficient.
        Use this when the source server requires SQL authentication or when running under a service account that lacks access to the source instance.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances where endpoints will be created. Must have sysadmin access to create endpoint objects.
        Use this to deploy endpoints across multiple servers in Always On configurations or Service Broker scenarios requiring identical endpoint definitions.

    .PARAMETER DestinationSqlCredential
        Specifies alternative credentials for connecting to destination SQL Server instances. Applied to all destination servers when Windows Authentication is insufficient.
        Use this when destination servers require SQL authentication or when deploying endpoints across environments with different security contexts.

    .PARAMETER Endpoint
        Specifies which endpoints to copy from the source instance. Accepts endpoint names and supports wildcards for pattern matching.
        Use this when you need to migrate specific endpoints like Database Mirroring or Service Broker endpoints rather than copying all user-defined endpoints.

    .PARAMETER ExcludeEndpoint
        Specifies which endpoints to skip during the copy operation. Takes precedence over the Endpoint parameter when both are specified.
        Use this to exclude problematic or environment-specific endpoints while copying most other endpoints from the source instance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Drops and recreates existing endpoints on destination instances when name conflicts occur. By default, existing endpoints are skipped to prevent disruption.
        Use this when updating endpoint configurations or when you need to overwrite outdated endpoint definitions on destination servers.

    .NOTES
        Tags: Migration, Endpoint
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaEndpoint

    .EXAMPLE
        PS C:\> Copy-DbaEndpoint -Source sqlserver2014a -Destination sqlcluster

        Copies all server endpoints from sqlserver2014a to sqlcluster, using Windows credentials. If endpoints with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaEndpoint -Source sqlserver2014a -SourceSqlCredential $cred -Destination sqlcluster -Endpoint tg_noDbDrop -Force

        Copies only the tg_noDbDrop endpoint from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an endpoint with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaEndpoint -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

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
        [object[]]$Endpoint,
        [object[]]$ExcludeEndpoint,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverEndpoints = $sourceServer.Endpoints | Where-Object IsSystemObject -eq $false

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destEndpoints = $destServer.Endpoints

            foreach ($currentEndpoint in $serverEndpoints) {
                $endpointName = $currentEndpoint.Name

                $copyEndpointStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $endpointName
                    Type              = "Endpoint"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Endpoint -and $Endpoint -notcontains $endpointName -or $ExcludeEndpoint -contains $endpointName) {
                    continue
                }

                if ($destEndpoints.Name -contains $endpointName) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Server endpoint $endpointName exists at destination. Use -Force to drop and migrate.")) {
                            $copyEndpointStatus.Status = "Skipped"
                            $copyEndpointStatus.Notes = "Already exists on destination"
                            $copyEndpointStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Server endpoint $endpointName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server endpoint $endpointName and recreating.")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server endpoint $endpointName."
                                $destServer.Endpoints[$endpointName].Drop()
                            } catch {
                                $copyEndpointStatus.Status = "Failed"
                                $copyEndpointStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyEndpointStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping server endpoint $endpointName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server endpoint $endpointName.")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying server endpoint $endpointName."
                        $destServer.Query($currentEndpoint.Script()) | Out-Null
                        $copyEndpointStatus.Status = "Successful"
                        $copyEndpointStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyEndpointStatus.Status = "Failed"
                        $copyEndpointStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyEndpointStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating server endpoint $endpointName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}