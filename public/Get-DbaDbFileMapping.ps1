function Get-DbaDbFileMapping {
    <#
    .SYNOPSIS
        Creates file mapping hashtable from existing database for use in restore operations

    .DESCRIPTION
        Extracts the logical-to-physical file name mappings from an existing database and returns them in a hashtable format compatible with Restore-DbaDatabase. This eliminates the need to manually specify file paths when restoring databases to different servers or locations. The function reads both data files and log files from the database's file groups and creates a complete mapping that preserves the original file structure during restore operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER InputObject
        Database object piped in from Get-DbaDatabase

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

    .EXAMPLE
        PS C:\> $filemap = Get-DbaDbFileMapping -SqlInstance sql2016 -Database test
        PS C:\> Get-ChildItem \\nas\db\backups\test | Restore-DbaDatabase -SqlInstance sql2019 -Database test -FileMapping $filemap.FileMapping

        Restores test to sql2019 using the file structure built from the existing database on sql2016
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
            if ($db.IsAccessible) {
                Write-Message -Level Verbose -Message "Processing database: $db"
                $fileMap = @{ }

                foreach ($file in $db.FileGroups.Files) {
                    $fileMap[$file.Name] = $file.FileName
                }
                foreach ($file in $db.LogFiles) {
                    $fileMap[$file.Name] = $file.FileName
                }

                [PSCustomObject]@{
                    ComputerName = $db.ComputerName
                    InstanceName = $db.InstanceName
                    SqlInstance  = $db.SqlInstance
                    Database     = $db.Name
                    FileMapping  = $fileMap
                }
            } else {
                Write-Message -Level Verbose -Message "Skipping processing of database: $db as database is not accessible"
            }
        }
    }
}