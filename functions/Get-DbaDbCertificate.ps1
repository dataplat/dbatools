function Get-DbaDbCertificate {
    <#
.SYNOPSIS
Gets database certificates

.DESCRIPTION
Gets database certificates

.PARAMETER SqlInstance
The target SQL Server instance

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
Get certificate from specific database

.PARAMETER ExcludeDatabase
Database(s) to ignore when retrieving certificates.

.PARAMETER Certificate
Get specific certificate

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Certificate
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
Get-DbaDbCertificate -SqlInstance sql2016

Gets all certificates

.EXAMPLE
Get-DbaDbCertificate -SqlInstance Server1 -Database db1

Gets the certificate for the db1 database

.EXAMPLE
Get-DbaDbCertificate -SqlInstance Server1 -Database db1 -Certificate cert1

Gets the cert1 certificate within the db1 database

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Certificate,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaDatabaseCertificate
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = Get-DbaDatabase -SqlInstance $server | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "$db is not accessible, skipping"
                    continue
                }
                $dbName = $db.Name
                $currentdb = $server.Databases[$dbName]

                if ($null -eq $currentdb) {
                    Write-Message -Message "Database '$db' does not exist on $instance" -Target $currentdb -Level Verbose
                    continue
                }

                if ($null -eq $currentdb.Certificates) {
                    Write-Message -Message "No certificate exists in the $db database on $instance" -Target $currentdb -Level Verbose
                    continue
                }

                $certs = $currentdb.Certificates
                if ($Certificate) {
                    $certs = $certs | Where-Object Name -in $Certificate
                }

                foreach ($cert in $certs) {

                    Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $cert -MemberType NoteProperty -Name Database -value $currentdb.Name

                    Select-DefaultView -InputObject $cert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
                }
            }
        }
    }
}