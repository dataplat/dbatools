function Get-DbaDbMasterKey {
    <#
    .SYNOPSIS
        Retrieves database master key information from SQL Server databases

    .DESCRIPTION
        Retrieves database master key objects and their metadata from one or more SQL Server databases. Database master keys are used to encrypt sensitive data through features like Transparent Data Encryption (TDE), column-level encryption, and certificate-based encryption. This function helps DBAs inventory encryption keys across their environment for security audits, compliance reporting, and encryption management. Returns key details including creation date, last modified date, and server encryption status.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for database master keys. Accepts wildcards for pattern matching.
        Use this when you need to audit encryption keys for specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when checking for master keys. Accepts wildcards for pattern matching.
        Use this to exclude system databases or databases you know don't use encryption features during security audits.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline for master key analysis.
        Use this when you need to check master keys for databases that match specific criteria like compatibility level or size.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.MasterKey

        Returns one MasterKey object per database that contains a master key. If a database does not have a master key, it is skipped (no output for that database).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database containing the master key
        - CreateDate: DateTime when the master key was created
        - DateLastModified: DateTime when the master key was last modified
        - IsEncryptedByServer: Boolean indicating if the master key is encrypted by the server master key

        All properties from the base SMO MasterKey object are accessible via Select-Object *.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMasterKey

    .EXAMPLE
        PS C:\> Get-DbaDbMasterKey -SqlInstance sql2016

        Gets all master database keys

    .EXAMPLE
        PS C:\> Get-DbaDbMasterKey -SqlInstance Server1 -Database db1

        Gets the master key for the db1 database

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database -ExcludeDatabase $ExcludeDatabase -SqlCredential $SqlCredential
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db on $($db.Parent) is not accessible. Skipping."
                continue
            }
            $instance = $db.Parent.Name
            $masterkey = $db.MasterKey

            if (!$masterkey) {
                Write-Message -Message "No master key exists in the $db database on $instance" -Target $db -Level Verbose
                continue
            }

            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

            Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
        }
    }
}