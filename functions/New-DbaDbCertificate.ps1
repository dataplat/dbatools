function New-DbaDbCertificate {
    <#
.SYNOPSIS
Creates a new database certificate

.DESCRIPTION
Creates a new database certificate. If no database is specified, the certificate will be created in master.

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the certificate will be created. Defaults to master.

.PARAMETER Name
Optional name to create the certificate. Defaults to database name.

.PARAMETER Subject
Optional subject to create the certificate.

.PARAMETER StartDate
Optional secure string used to create the certificate.

.PARAMETER ExpirationDate
Optional secure string used to create the certificate.

.PARAMETER ActiveForServiceBrokerDialog
Optional secure string used to create the certificate.

.PARAMETER Password
Optional password - if no password is supplied, the password will be protected by the master key

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

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
New-DbaDbCertificate -SqlInstance Server1

You will be prompted to securely enter your password, then a certificate will be created in the master database on server1 if it does not exist.

.EXAMPLE
New-DbaDbCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a certificate in the 'db1' database
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [object[]]$Database = "master",
        [string[]]$Subject,
        [datetime]$StartDate = (Get-Date),
        [datetime]$ExpirationDate = $StartDate.AddYears(5),
        [switch]$ActiveForServiceBrokerDialog,
        [Security.SecureString]$Password,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias New-DbaDatabaseCertificate
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

            foreach ($db in $Database) {

                $currentdb = $server.Databases[$db] | Where-Object IsAccessible

                if ($null -eq $currentdb) {
                    Stop-Function -Message "Database '$db' does not exist on $instance" -Target $server -Continue
                }

                if ($null -eq $name) {
                    Write-Message -Level Verbose -Message "Name is NULL, setting it to '$db'"
                    $name = $db
                }
                if ($null -eq $subject) {
                    Write-Message -Level Verbose -Message "Subject is NULL, setting it to '$db Database Certificate'"
                    $subject = "$db Database Certificate"
                }

                foreach ($cert in $name) {
                    if ($null -ne $currentdb.Certificates[$cert]) {
                        Stop-Function -Message "Certificate '$cert' already exists in the $db database on $instance" -Target $currentdb -Continue
                    }

                    if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating certificate for database '$db' on $instance")) {
                        try {
                            $smocert = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Certificate $currentdb, $cert

                            $smocert.StartDate = $StartDate
                            $smocert.Subject = $Subject
                            $smocert.ExpirationDate = $ExpirationDate
                            $smocert.ActiveForServiceBrokerDialog = $ActiveForServiceBrokerDialog

                            if ($password.Length -gt 0) {
                                $smocert.Create(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password))))
                            }
                            else {
                                $smocert.Create()
                            }

                            Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name ComputerName -value $server.NetName
                            Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                            Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                            Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name Database -value $currentdb.Name

                            Select-DefaultView -InputObject $smocert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
                        }
                        catch {
                            if ($_.Exception.InnerException) {
                                $exception = $_.Exception.InnerException.ToString() -Split "System.Data.SqlClient.SqlException: "
                                $exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
                            }
                            else {
                                $exception = $_.Exception
                            }

                            Stop-Function -Message "Failed to create certificate in $db on $instance. Exception: $exception" -Target $smocert -InnerErrorRecord $_ -Continue
                        }
                    }
                }
            }
        }
    }
}