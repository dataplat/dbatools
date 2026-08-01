function Get-DbaDbFileMapping {
    <#
    .SYNOPSIS
        Creates file mapping hashtable from existing database for use in restore operations

    .DESCRIPTION
        Extracts the logical-to-physical file name mappings from an existing database and returns them in a hashtable format compatible with Restore-DbaDatabase. This eliminates the need to manually specify file paths when restoring databases to different servers or locations. The function reads both data files and log files from the database's file groups and creates a complete mapping that preserves the original file structure during restore operations.

        Databases that cannot be opened - RESTORING, RECOVERY_PENDING, SUSPECT or OFFLINE - are read through Get-DbaDbFile, which takes their file layout from sys.master_files. That covers the mapping of a database left in NORECOVERY by a full restore, which is what a following differential restore needs.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to extract file mappings from. Accepts wildcards for pattern matching.
        Use this when you need file mappings for specific databases instead of all databases on the instance.

    .PARAMETER InputObject
        Accepts database objects directly from Get-DbaDatabase or other dbatools database functions via pipeline.
        Use this when you want to chain database operations or work with pre-filtered database collections.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, File, Data, Log, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net | Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFileMapping

    .OUTPUTS
        PSCustomObject

        Returns one object per database provided as input, including databases that are not accessible. Each object contains the file mapping information needed for restore operations.

        Properties:
        - ComputerName: The name of the computer where the SQL Server instance is running
        - InstanceName: The instance name of the SQL Server (e.g., "MSSQLSERVER" or "SQLEXPRESS")
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database from which file mappings were extracted
        - FileMapping: A hashtable mapping logical file names (keys) to their physical file paths (values), compatible with Restore-DbaDatabase

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Get-ChildItem \\nas\db\backups\test | Restore-DbaDatabase -SqlInstance sql2019 -Database test -FileMapping $filemap.FileMapping

        Restores test to sql2019 using the file structure built from the existing database on sql2016

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Restore-DbaDatabase -SqlInstance sql2016 -Path \\nas\db\backups\test\test_diff.bak -DatabaseName test -Continue -FileMapping $filemap.FileMapping

        Builds the file mapping of test while it is still in NORECOVERY from an earlier full restore, then applies the differential backup on top of it
    #>
    [CmdletBinding()]
    param ([parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -not 'SqlInstance', 'InputObject') {
            Write-Message -Level Warning -Message "You must specify either a SQL instance or supply an InputObject"
            return
        }

        if (Test-Bound -Not -ParameterName InputObject) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            Write-Message -Level Verbose -Message "Processing database: $db"
            $fileMap = @{ }

            if ($db.IsAccessible) {
                foreach ($file in $db.FileGroups.Files) {
                    $fileMap[$file.Name] = $file.FileName
                }
                foreach ($file in $db.LogFiles) {
                    $fileMap[$file.Name] = $file.FileName
                }
            } else {
                # SMO cannot enumerate the files of a database it cannot open, so take the layout that
                # Get-DbaDbFile reads out of sys.master_files. This is the case that matters between a
                # NORECOVERY full restore and the differential that follows it.
                Write-Message -Level Verbose -Message "Database $db is not accessible, building the mapping from the file layout in master"

                $files = Get-DbaDbFile -InputObject $db -EnableException:$EnableException
                if (-not $files) {
                    Write-Message -Level Verbose -Message "Skipping processing of database: $db as no file information was returned for it"
                    continue
                }

                foreach ($file in $files) {
                    $fileMap[$file.LogicalName] = $file.PhysicalName
                }
            }

            [PSCustomObject]@{
                ComputerName = $db.ComputerName
                InstanceName = $db.InstanceName
                SqlInstance  = $db.SqlInstance
                Database     = $db.Name
                FileMapping  = $fileMap
            }
        }
    }
}