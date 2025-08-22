function Get-DbaDbEncryptionKey {
    <#
    .SYNOPSIS
        Retrieves Transparent Data Encryption (TDE) database encryption keys from SQL Server databases

    .DESCRIPTION
        Retrieves detailed information about Transparent Data Encryption (TDE) database encryption keys including encryption state, algorithm, and certificate details. This function helps DBAs audit encrypted databases, verify TDE configuration, and gather key information for compliance reporting or troubleshooting encryption issues. Returns comprehensive key properties like thumbprint, encryption type, and important dates for certificate rotation planning.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Get encryption key from specific database

    .PARAMETER ExcludeDatabase
        Database(s) to ignore when retrieving encryption keys

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbEncryptionKey

    .EXAMPLE
        PS C:\> Get-DbaDbEncryptionKey -SqlInstance sql2016

        Gets all encryption keys from sql2016

    .EXAMPLE
        PS C:\> Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1

        Gets the encryption key for the db1 database on the sql01 instance

    .EXAMPLE
        PS C:\> Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -Certificate cert1

        Gets the cert1 encryption key within the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -Subject 'Availability Group Cert'

        Gets the encryption key within the db1 database that has the subject 'Availability Group Cert' on sql01

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
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (-not $db.IsAccessible) {
                Write-Message -Level Warning -Message "$db is not accessible, skipping"
                continue
            }

            $keys = $db.DatabaseEncryptionKey | Where-Object EncryptionAlgorithm

            if ($null -eq $keys) {
                Write-Message -Message "No encryption key exists in the $db database on $($db.Parent.Name)" -Target $db -Level Verbose
                continue
            }

            foreach ($key in $keys) {
                Add-Member -Force -InputObject $key -MemberType NoteProperty -Name ComputerName -value $db.ComputerName
                Add-Member -Force -InputObject $key -MemberType NoteProperty -Name InstanceName -value $db.InstanceName
                Add-Member -Force -InputObject $key -MemberType NoteProperty -Name SqlInstance -value $db.SqlInstance
                Add-Member -Force -InputObject $key -MemberType NoteProperty -Name Database -value $db.Name

                Select-DefaultView -InputObject $key -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, EncryptionAlgorithm, EncryptionState, EncryptionType, EncryptorName, ModifyDate, OpenedDate, RegenerateDate, SetDate, Thumbprint
            }
        }
    }
}