function Copy-DbaExtendedStoredProcedure {
    <#
    .SYNOPSIS
        Copies custom Extended Stored Procedures (XPs) and their associated DLL files between SQL Server instances

    .DESCRIPTION
        Migrates custom Extended Stored Procedures from the source server to one or more destination servers. Extended Stored Procedures are DLL-based procedures that extend SQL Server functionality by calling external code, commonly used for custom server operations, legacy integrations, or specialized processing tasks.

        This function identifies custom Extended Stored Procedures (excludes system XPs), copies their definitions to the destination, and attempts to copy the associated DLL files to the destination server's Binn directory. Due to OS and .NET version differences, DLLs may require recompilation when migrating between different Windows versions or SQL Server versions.

        By default, all custom Extended Stored Procedures are copied. Use -ExtendedProcedure to copy specific procedures or -ExcludeExtendedProcedure to skip certain ones. Existing procedures on the destination are skipped unless -Force is used to overwrite them.

        WARNING: DLL files may not be compatible between different OS versions (e.g., Windows Server 2012 R2 to Windows Server 2019) due to .NET framework differences. The function will attempt to copy DLL files but will warn if the copy fails, allowing for manual intervention.

    .PARAMETER Source
        The source SQL Server instance containing Extended Stored Procedures to copy. Requires sysadmin access to read procedure definitions and access to DLL files in the Binn directory.
        Use this to specify which server has the Extended Stored Procedures you want to migrate or standardize across your environment.

    .PARAMETER SourceSqlCredential
        Credentials for connecting to the source SQL Server instance when Windows authentication is not available or desired.
        Use this when you need to connect with specific SQL login credentials or when running under a service account that lacks access to the source server.

    .PARAMETER Destination
        The destination SQL Server instance(s) where Extended Stored Procedures will be copied. Requires sysadmin access to create procedures and file system access to copy DLL files.
        Accepts multiple destinations to deploy Extended Stored Procedures across several servers simultaneously for standardization.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance(s) when Windows authentication is not available or desired.
        Use this when deploying to servers that require different authentication credentials or when your current context lacks destination access.

    .PARAMETER ExtendedProcedure
        Specifies which Extended Stored Procedures to copy from the source server instead of copying all available custom XPs.
        Use this when you only need specific procedures migrated, such as copying just certain legacy integrations while leaving others behind.

    .PARAMETER ExcludeExtendedProcedure
        Specifies which Extended Stored Procedures to skip during the copy operation while processing all others from the source.
        Use this when most Extended Stored Procedures should be copied but specific ones need to remain server-specific or are problematic.

    .PARAMETER DestinationPath
        Specifies the destination path where DLL files should be copied. By default, uses the destination SQL Server's Binn directory.
        Use this when you need to copy DLLs to a non-standard location or when the destination Binn directory is not accessible.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Overwrites existing Extended Stored Procedures on the destination server instead of skipping them when name conflicts occur.
        Use this when updating existing procedures with newer versions or when you need to ensure destination procedures match the source exactly.

    .OUTPUTS
        PSCustomObject (MigrationObject)

        Returns one object per Extended Stored Procedure processed. The object contains information about the success or failure of the copy operation.

        Properties:
        - DateTime: The date and time when the copy operation was processed (DbaDateTime)
        - SourceServer: The name of the source SQL Server instance (string)
        - DestinationServer: The name of the destination SQL Server instance (string)
        - Name: The name of the Extended Stored Procedure (string)
        - Type: Always "Extended Stored Procedure" (string)
        - Status: The result of the operation - Successful, Skipped, Failed, or "Successful (DLL not copied)" (string)
        - Notes: Additional information about the operation result, such as reason for skip, error message, or DLL copy status (string)
        - Schema: The schema in which the Extended Stored Procedure was created (string)

    .NOTES
        Tags: Migration, ExtendedStoredProcedure, XP
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers, file system access for DLL copying

    .LINK
        https://dbatools.io/Copy-DbaExtendedStoredProcedure

    .EXAMPLE
        PS C:\> Copy-DbaExtendedStoredProcedure -Source sqlserver2014a -Destination sqlcluster

        Copies all custom Extended Stored Procedures from sqlserver2014a to sqlcluster using Windows credentials. If procedures with the same name exist on sqlcluster, they will be skipped. Attempts to copy associated DLL files.

    .EXAMPLE
        PS C:\> Copy-DbaExtendedStoredProcedure -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -ExtendedProcedure xp_custom_proc -Force

        Copies only the Extended Stored Procedure xp_custom_proc from sqlserver2014a to sqlcluster using SQL credentials. If the procedure already exists on sqlcluster, it will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaExtendedStoredProcedure -Source sqlserver2014a -Destination sqlcluster -ExcludeExtendedProcedure xp_old_proc -Force

        Copies all custom Extended Stored Procedures found on sqlserver2014a except xp_old_proc to sqlcluster. If procedures with the same name exist on sqlcluster, they will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaExtendedStoredProcedure -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Copy-DbaExtendedStoredProcedure -Source sqlserver2014a -Destination sqlcluster -DestinationPath "C:\CustomPath"

        Copies all custom Extended Stored Procedures and attempts to copy DLL files to C:\CustomPath on the destination server instead of the default Binn directory.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$ExtendedProcedure,
        [string[]]$ExcludeExtendedProcedure,
        [string]$DestinationPath,
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

        # Query to get custom Extended Stored Procedures
        # System XPs typically start with xp_ and are in resource database or have DLL in system paths
        # Custom XPs are user-created and we'll identify them
        $sql = @"
SELECT
    p.name AS ProcedureName,
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.object_id,
    m.definition AS DllPath
FROM sys.procedures p
INNER JOIN sys.all_objects o ON p.object_id = o.object_id
LEFT JOIN sys.sql_modules m ON p.object_id = m.object_id
WHERE p.type = 'X'
    AND p.is_ms_shipped = 0
ORDER BY p.name
"@

        try {
            $sourceXPs = $sourceServer.Query($sql)
        } catch {
            Stop-Function -Message "Failed to query Extended Stored Procedures from source: $PSItem" -Target $Source -ErrorRecord $_
            return
        }

        if (-not $sourceXPs) {
            Write-Message -Level Verbose -Message "No custom Extended Stored Procedures found on source server"
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destInstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue
            }

            # Get destination XPs
            try {
                $destXPs = $destServer.Query($sql)
            } catch {
                Stop-Function -Message "Failed to query Extended Stored Procedures from destination: $PSItem" -Target $destInstance -ErrorRecord $_ -Continue
            }

            # Get destination Binn path if not specified
            if (-not $DestinationPath) {
                try {
                    $destBinnPath = $destServer.RootDirectory + "\Binn"
                } catch {
                    Write-Message -Level Warning -Message "Could not determine destination Binn directory. DLL files will not be copied."
                    $destBinnPath = $null
                }
            } else {
                $destBinnPath = $DestinationPath
            }

            # Get source Binn path
            try {
                $sourceBinnPath = $sourceServer.RootDirectory + "\Binn"
            } catch {
                Write-Message -Level Warning -Message "Could not determine source Binn directory. DLL files will not be copied."
                $sourceBinnPath = $null
            }

            foreach ($currentXP in $sourceXPs) {
                $xpName = $currentXP.ProcedureName
                $xpSchema = $currentXP.SchemaName
                $xpFullName = "$xpSchema.$xpName"

                $copyXPStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $xpName
                    Schema            = $xpSchema
                    Type              = "Extended Stored Procedure"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                # Filter by include/exclude
                if ($ExtendedProcedure -and ($ExtendedProcedure -notcontains $xpName)) {
                    continue
                }

                if ($ExcludeExtendedProcedure -and ($ExcludeExtendedProcedure -contains $xpName)) {
                    continue
                }

                # Check if exists on destination
                $existsOnDest = $destXPs | Where-Object ProcedureName -eq $xpName

                if ($existsOnDest) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destInstance, "Extended Stored Procedure $xpFullName exists at destination. Use -Force to drop and migrate.")) {
                            $copyXPStatus.Status = "Skipped"
                            $copyXPStatus.Notes = "Already exists on destination"
                            $copyXPStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Extended Stored Procedure $xpFullName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destInstance, "Dropping Extended Stored Procedure $xpFullName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping Extended Stored Procedure $xpFullName"
                                # Get DLL name before dropping
                                $dropXP = $destXPs | Where-Object ProcedureName -eq $xpName
                                $dropDllName = $null
                                if ($dropXP.DllPath) {
                                    $dropDllName = Split-Path $dropXP.DllPath -Leaf
                                }
                                $dropSql = "EXEC dbo.sp_dropextendedproc @functname = N'$xpFullName'"
                                $null = $destServer.Query($dropSql)
                            } catch {
                                $copyXPStatus.Status = "Failed"
                                $copyXPStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyXPStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping Extended Stored Procedure $xpFullName on $destInstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destInstance, "Creating Extended Stored Procedure $xpFullName")) {
                    try {
                        # Get DLL information from source
                        $sourceDllPath = $currentXP.DllPath
                        if (-not $sourceDllPath) {
                            # Try to get from sys.extended_procedures or sp_helpextendedproc
                            $dllQuery = "EXEC dbo.sp_helpextendedproc @funcname = N'$xpFullName'"
                            $dllInfo = $sourceServer.Query($dllQuery)
                            if ($dllInfo) {
                                $sourceDllPath = $dllInfo[0].DLL
                            }
                        }

                        if (-not $sourceDllPath) {
                            $copyXPStatus.Status = "Failed"
                            $copyXPStatus.Notes = "Could not determine DLL path for Extended Stored Procedure"
                            $copyXPStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Warning -Message "Could not determine DLL path for Extended Stored Procedure $xpFullName. Manual intervention required."
                            continue
                        }

                        $dllFileName = Split-Path $sourceDllPath -Leaf
                        $dllCopied = $false
                        $dllCopyNotes = $null

                        # Attempt to copy DLL file
                        if ($sourceBinnPath -and $destBinnPath) {
                            $sourceDllFullPath = Join-Path $sourceBinnPath $dllFileName
                            $destDllFullPath = Join-Path $destBinnPath $dllFileName

                            # Check if source DLL exists
                            $sourceComputerName = $sourceServer.ComputerName
                            $destComputerName = $destServer.ComputerName

                            try {
                                # Use UNC paths for remote copying
                                $sourceUncPath = "\\$sourceComputerName\$($sourceDllFullPath -replace ':', '$')"
                                $destUncPath = "\\$destComputerName\$($destDllFullPath -replace ':', '$')"

                                if (Test-Path $sourceUncPath) {
                                    Write-Message -Level Verbose -Message "Copying DLL from $sourceUncPath to $destUncPath"
                                    Copy-Item -Path $sourceUncPath -Destination $destUncPath -Force -ErrorAction Stop
                                    $dllCopied = $true
                                    Write-Message -Level Verbose -Message "Successfully copied DLL file"
                                } else {
                                    $dllCopyNotes = "Source DLL not found at expected path: $sourceDllFullPath"
                                    Write-Message -Level Warning -Message $dllCopyNotes
                                }
                            } catch {
                                $dllCopyNotes = "Failed to copy DLL file: $PSItem. DLL may need to be copied manually or recompiled for OS/SQL version compatibility."
                                Write-Message -Level Warning -Message $dllCopyNotes
                            }
                        } else {
                            $dllCopyNotes = "Could not determine source or destination Binn paths. DLL must be copied manually."
                            Write-Message -Level Warning -Message $dllCopyNotes
                        }

                        # Create the Extended Stored Procedure
                        $destDllPath = if ($dllCopied) { $destDllFullPath } else { $sourceDllPath }
                        $createSql = "EXEC dbo.sp_addextendedproc @functname = N'$xpFullName', @dllname = N'$destDllPath'"

                        Write-Message -Level Verbose -Message "Creating Extended Stored Procedure $xpFullName"
                        Write-Message -Level Debug -Message $createSql

                        $null = $destServer.Query($createSql)

                        $copyXPStatus.Status = if ($dllCopied) { "Successful" } else { "Successful (DLL not copied)" }
                        $copyXPStatus.Notes = $dllCopyNotes
                        $copyXPStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        if (-not $dllCopied) {
                            Write-Message -Level Warning -Message "Extended Stored Procedure $xpFullName created but DLL was not copied. You may need to manually copy the DLL file and ensure it's compatible with the destination OS/SQL version."
                        }
                    } catch {
                        $copyXPStatus.Status = "Failed"
                        $copyXPStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyXPStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating Extended Stored Procedure $xpFullName on $destInstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}
