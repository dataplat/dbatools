function Copy-DbaDataCollector {
    <#
    .SYNOPSIS
        Migrates user SQL Data Collector collection sets. SQL Data Collector configuration is on the agenda, but it's hard.

    .DESCRIPTION
        By default, all data collector objects are migrated. If the object already exists on the destination, it will be skipped unless -Force is used.

        The -CollectionSet parameter is auto-populated for command-line completion and can be used to copy only specific objects.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER CollectionSet
        The collection set(s) to process - this list is auto-populated from the server. If unspecified, all collection sets will be processed.

    .PARAMETER ExcludeCollectionSet
        The collection set(s) to exclude - this list is auto-populated from the server

    .PARAMETER NoServerReconfig
        Upcoming parameter to enable server reconfiguration

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        If collection sets exists on destination server, it will be dropped and recreated.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration,DataCollection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDataCollector

    .EXAMPLE
        PS C:\> Copy-DbaDataCollector -Source sqlserver2014a -Destination sqlcluster

        Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using Windows credentials.

    .EXAMPLE
        PS C:\> Copy-DbaDataCollector -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaDataCollector -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Copy-DbaDataCollector -Source sqlserver2014a -Destination sqlcluster -CollectionSet 'Server Activity', 'Table Usage Analysis'

        Copies two Collection Sets, Server Activity and Table Usage Analysis, from sqlserver2014a to sqlcluster.

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
        [object[]]$CollectionSet,
        [object[]]$ExcludeCollectionSet,
        [switch]$NoServerReconfig,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaDataCollector does not support Linux - we're still waiting for the Core SMOs from Microsoft"
            return
        }
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
        $sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
        $sourceStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $sourceSqlStoreConnection
        $configDb = $sourceStore.ScriptAlter().GetScript() | Out-String
        $configDb = $configDb -replace [Regex]::Escape("'$source'"), "'$destReplace'"

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
            if ($NoServerReconfig -eq $false) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time.")) {
                    Write-Message -Level Verbose -Message "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time."
                    $NoServerReconfig = $true

                    <# for future use when this support is added #>
                    $copyServerConfigStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = $userName
                        Type              = "Data Collection Server Config"
                        Status            = "Skipped"
                        Notes             = "Not supported at this time"
                        DateTime          = [DbaDateTime](Get-Date)
                    }
                    $copyServerConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
            $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
            $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
            $destStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $destSqlStoreConnection

            if (!$NoServerReconfig) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to modify Data Collector configuration")) {
                    try {
                        $sql = "Unknown at this time"
                        $destServer.Query($sql)
                        $destStore.Alter()
                    } catch {
                        $copyServerConfigStatus.Status = "Failed"
                        $copyServerConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue modifying Data Collector configuration" -Target $destServer -ErrorRecord $_
                    }
                }
            }

            if ($destStore.Enabled -eq $false) {
                Write-Message -Level Verbose -Message "The Data Collector must be setup initially for Collection Sets to be migrated. Setup the Data Collector and try again."
                continue
            }

            $storeCollectionSets = $sourceStore.CollectionSets | Where-Object { $_.IsSystem -eq $false }
            if ($CollectionSet) {
                $storeCollectionSets = $storeCollectionSets | Where-Object Name -In $CollectionSet
            }
            if ($ExcludeCollectionSet) {
                $storeCollectionSets = $storeCollectionSets | Where-Object Name -NotIn $ExcludeCollectionSet
            }

            Write-Message -Level Verbose -Message "Migrating collection sets"
            foreach ($set in $storeCollectionSets) {
                $collectionName = $set.Name

                $copyCollectionSetStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $collectionName
                    Type              = "Collection Set"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.CollectionSets[$collectionName]) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Collection Set '$collectionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate")) {
                            Write-Message -Level Verbose -Message "Collection Set '$collectionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate"

                            $copyCollectionSetStatus.Status = "Skipped"
                            $copyCollectionSetStatus.Notes = "Already exists on destination"
                            $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $collectionName")) {
                            Write-Message -Level Verbose -Message "Collection Set '$collectionName' exists on $destinstance"
                            Write-Message -Level Verbose -Message "Force specified. Dropping $collectionName."

                            try {
                                $destStore.CollectionSets[$collectionName].Drop()
                            } catch {
                                $copyCollectionSetStatus.Status = "Failed to drop on destination"
                                $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue dropping collection" -Target $collectionName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating collection set $collectionName")) {
                    try {
                        $sql = $set.ScriptCreate().GetScript() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Migrating collection set $collectionName"
                        $destServer.Query($sql)

                        $copyCollectionSetStatus.Status = "Successful"
                        $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyCollectionSetStatus.Status = "Failed to create collection"
                        $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)

                        Stop-Function -Message "Issue creating collection set" -Target $collectionName -ErrorRecord $_
                    }

                    try {
                        if ($set.IsRunning) {
                            Write-Message -Level Verbose -Message "Starting collection set $collectionName"
                            $destStore.CollectionSets.Refresh()
                            $destStore.CollectionSets[$collectionName].Start()
                        }

                        $copyCollectionSetStatus.Status = "Successful started Collection"
                        $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyCollectionSetStatus.Status = "Failed to start collection"
                        $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue starting collection set" -Target $collectionName -ErrorRecord $_
                    }
                }
            }
        }
    }
}