function Get-DbaDbCertificate {
    <#
    .SYNOPSIS
        Gets database certificates

    .DESCRIPTION
        Gets database certificates

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Get certificate from specific database

    .PARAMETER ExcludeDatabase
        Database(s) to ignore when retrieving certificates

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER Certificate
        Get specific certificate by name

    .PARAMETER Certificate
        Get specific certificate by subject

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate
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

                Select-DefaultView -InputObject $cert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
            }
        }
    }
}