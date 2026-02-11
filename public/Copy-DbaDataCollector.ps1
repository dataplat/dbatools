function Copy-DbaDataCollector {
    <#
    .SYNOPSIS
        Copies SQL Data Collector collection sets from one instance to another

    .DESCRIPTION
        Copies SQL Data Collector collection sets between SQL Server instances, allowing you to replicate performance monitoring configurations across your environment. This command scripts out the collection set definitions from the source instance and recreates them on the destination, preserving all collection items, schedules, and upload settings.

        By default, all user-defined collection sets are migrated. If a collection set already exists on the destination, it will be skipped unless -Force is used to drop and recreate it. Collection sets that were running on the source will automatically be started on the destination after migration.

        The -CollectionSet parameter is auto-populated for command-line completion and can be used to copy only specific collection sets. Note that Data Collector must already be configured and enabled on the destination instance before running this command.

    .PARAMETER Source
        Source SQL Server instance containing the Data Collector collection sets to copy. Requires sysadmin access and SQL Server 2008 or higher.
        The Data Collector feature must be configured on this instance for collection sets to exist.

    .PARAMETER SourceSqlCredential
        Login credentials for the source SQL Server instance. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server instance(s) where collection sets will be created. Requires sysadmin access and SQL Server 2008 or higher.
        The Data Collector feature must already be configured and enabled on the destination before running this command.

    .PARAMETER DestinationSqlCredential
        Login credentials for the destination SQL Server instance(s). Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER CollectionSet
        Specific collection set names to copy from the source instance. Supports tab completion with available collection sets.
        When omitted, all user-defined collection sets are copied (system collection sets are always excluded).

    .PARAMETER ExcludeCollectionSet
        Collection set names to exclude from the copy operation. Supports tab completion with available collection sets.
        Useful when you want to copy most collection sets but skip specific ones due to environment differences.

    .PARAMETER NoServerReconfig
        Reserved parameter for future Data Collector server configuration copying functionality.
        Currently has no effect as server-level configuration copying is not yet implemented.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Drops and recreates collection sets that already exist on the destination server.
        Without this switch, existing collection sets are skipped to prevent accidental data loss.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per collection set or configuration operation performed with TypeName dbatools.MigrationObject.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: The date and time the operation was performed (DbaDateTime type)
        - SourceServer: The name of the source SQL Server instance
        - DestinationServer: The name of the destination SQL Server instance
        - Name: The name of the collection set or configuration item being copied
        - Type: The type of object being copied (e.g., "Collection Set", "Data Collection Server Config")
        - Status: Result of the operation (Successful, Skipped, Failed, etc.)
        - Notes: Additional information about the operation, such as skip reasons or error details

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
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
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
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if ($NoServerReconfig -eq $false) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time.")) {
                    Write-Message -Level Verbose -Message "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time."
                    $NoServerReconfig = $true

                    <# for future use when this support is added #>
                    $copyServerConfigStatus = [PSCustomObject]@{
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

                $copyCollectionSetStatus = [PSCustomObject]@{
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
                                $copyCollectionSetStatus.Status = "Failed to drop collection $collectionName on $destinstance"
                                $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Failed to drop collection $collectionName on $destinstance | $PSItem"
                                continue
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
                        Write-Message -Level Verbose -Message "Issue creating collection $collectionName on $destinstance | $PSItem"
                        continue
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
                        Write-Message -Level Verbose -Message "Issue starting collection $collectionName on $destinstance | $PSItem"
                    }
                }
            }
        }
    }
}