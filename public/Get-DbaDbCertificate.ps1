function Get-DbaDbCertificate {
    <#
    .SYNOPSIS
        Retrieves database-level certificates from SQL Server databases for security auditing and certificate management

    .DESCRIPTION
        Retrieves all certificates stored within SQL Server databases, providing detailed information about each certificate including expiration dates, issuers, and encryption properties. This function is essential for DBAs managing Transparent Data Encryption (TDE), Service Broker security, or other database-level encryption features. Use this to audit certificate inventory across your environment, monitor approaching expiration dates for proactive renewal planning, and ensure compliance with security policies that require certificate tracking and rotation.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for certificates. Accepts one or more database names as strings.
        Use this when you need to audit certificates in specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip when retrieving certificates. Accepts one or more database names as strings.
        Useful when you want to audit most databases but exclude system databases or specific databases that don't contain certificates of interest.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the PowerShell pipeline.
        This allows you to chain commands like Get-DbaDatabase | Get-DbaDbCertificate for more complex filtering scenarios.

    .PARAMETER Certificate
        Filters results to specific certificates by their name property. Accepts one or more certificate names as strings.
        Use this when you need to check the status of known certificates across multiple databases, such as tracking TDE certificates or Service Broker certificates.

    .PARAMETER Subject
        Filters results to certificates with specific subject names. Accepts one or more subject strings for exact matching.
        Helpful when searching for certificates based on their distinguished name or common name, particularly when certificate names aren't descriptive but subjects are standardized.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbCertificate

    .EXAMPLE
        PS C:\> Get-DbaDbCertificate -SqlInstance sql2016

        Gets all certificates

    .EXAMPLE
        PS C:\> Get-DbaDbCertificate -SqlInstance Server1 -Database db1

        Gets the certificate for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbCertificate -SqlInstance Server1 -Database db1 -Certificate cert1

        Gets the cert1 certificate within the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbCertificate -SqlInstance Server1 -Database db1 -Subject 'Availability Group Cert'

        Gets the certificate within the db1 database that has the subject 'Availability Group Cert'

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [object[]]$Certificate, # sometimes it's text, other times cert
        [string[]]$Subject,
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

            $certs = $db.Certificates

            if ($null -eq $certs) {
                Write-Message -Message "No certificate exists in the $db database on $instance" -Target $db -Level Verbose
                continue
            }

            if ($Certificate) {
                $certs = $certs | Where-Object Name -in $Certificate
            }

            if ($Subject) {
                $certs = $certs | Where-Object Subject -in $Subject
            }

            foreach ($cert in $certs) {
                Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name ComputerName -value $db.ComputerName
                Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name InstanceName -value $db.InstanceName
                Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name SqlInstance -value $db.SqlInstance
                Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name Database -value $db.Name
                Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name DatabaseId -value $db.Id

                Select-DefaultView -InputObject $cert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
            }
        }
    }
}