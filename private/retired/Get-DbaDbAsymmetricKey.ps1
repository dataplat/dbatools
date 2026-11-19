function Get-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Retrieves asymmetric keys from SQL Server databases for encryption management and security auditing

    .DESCRIPTION
        Retrieves asymmetric keys stored in SQL Server databases, including their encryption algorithms, key lengths, owners, and thumbprints.
        This function is essential for security audits and encryption key management, allowing DBAs to inventory all asymmetric keys across databases without manually querying system catalogs.
        Asymmetric keys are used for encryption, digital signatures, and certificate creation in SQL Server's transparent data encryption and column-level encryption features.
        Returns detailed key properties to help with compliance reporting and security assessments.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for asymmetric keys. Accepts wildcards for pattern matching.
        Use this when you need to audit encryption keys in specific databases instead of scanning all databases on the instance.
        Essential for targeted security assessments or compliance audits of particular applications.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the asymmetric key scan. Accepts wildcards for pattern matching.
        Use this to skip system databases, test databases, or databases known to not contain encryption keys.
        Helps focus audits on production databases and reduces noise in security assessments.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase.
        Use this to chain database filtering with key retrieval, such as getting keys from databases with specific properties.
        Enables advanced filtering scenarios like scanning only databases created after a certain date or with particular owners.

    .PARAMETER Name
        Filters results to asymmetric keys with specific names. Accepts wildcards and multiple key names.
        Use this when tracking specific keys during key rotation, compliance audits, or troubleshooting encryption issues.
        Common when validating that required encryption keys exist across multiple databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbAsymmetricKey

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance sql2016

        Gets all Asymmetric Keys

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1

        Gets the Asymmetric Keys for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Name key1

        Gets the key1 Asymmetric Key within the db1 database

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AsymmetricKey

        Returns one AsymmetricKey object per asymmetric key found in the specified databases. Each object represents a single asymmetric key stored in the database's encryption hierarchy.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the asymmetric key
        - Name: The name of the asymmetric key
        - Owner: The principal that owns the asymmetric key
        - KeyEncryptionAlgorithm: The encryption algorithm used for the key (RSA_512, RSA_1024, RSA_2048, RSA_3072, RSA_4096)
        - KeyLength: The length of the key in bits (512, 1024, 2048, 3072, or 4096)
        - PrivateKeyEncryptionType: How the private key is encrypted (NoEncryption, EncryptedByMasterKey, EncryptedByPassword)
        - Thumbprint: The thumbprint (fingerprint) of the asymmetric key for verification and identification

        Additional properties available (from SMO AsymmetricKey object):
        - DatabaseId: Unique identifier of the database containing the key
        - And all other standard SMO AsymmetricKey properties (use Select-Object * to see all)

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "$db is not accessible, skipping"
                continue
            }

            $akeys = $db.AsymmetricKeys

            if ($null -eq $akeys) {
                Write-Message -Message "No Asymmetic Keys exists in the $db database on $instance" -Target $db -Level Verbose
                continue
            }

            if ($Name) {
                $akeys = $akeys | Where-Object Name -in $Name
            }

            foreach ($akey in $akeys) {
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name ComputerName -value $db.ComputerName
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name InstanceName -value $db.InstanceName
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name SqlInstance -value $db.SqlInstance
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name Database -value $db.Name
                Add-Member -Force -InputObject $akey -MemberType NoteProperty -Name DatabaseId -value $db.Id

                Select-DefaultView -InputObject $akey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, KeyEncryptionAlgorithm, KeyLength, PrivateKeyEncryptionType, Thumbprint
            }
        }
    }
}