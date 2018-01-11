function Remove-DbaDbCertificate {
    <#
.SYNOPSIS
Deletes specified database certificate

.DESCRIPTION
Deletes specified database certificate

.PARAMETER SqlInstance
The SQL Server to create the certificates on.

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials.

.PARAMETER Database
The database where the certificate will be removed.

.PARAMETER Certificate
The certificate that will be removed

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.PARAMETER CertificateCollection
Internal parameter to support pipeline input

.NOTES
Tags: Certificate
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Remove-DbaDbCertificate -SqlInstance Server1

The certificate in the master database on server1 will be removed if it exists.

.EXAMPLE
Remove-DbaDbCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to remove the certificate in the 'db1' database and drops the key.


#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ParameterSetName = "instance")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [object[]]$Database,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [object[]]$Certificate,
        [parameter(ValueFromPipeline, ParameterSetName = "collection")]
        [Microsoft.SqlServer.Management.Smo.Certificate[]]$CertificateCollection,
        [switch][Alias('Silent')]$EnableException
    )
    begin {

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Remove-DbaDatabaseCertificate

        function drop-cert ($smocert) {
            $server = $smocert.Parent.Parent
            $instance = $server.DomainInstanceName
            $cert = $smocert.Name
            $db = $smocert.Parent.Name

            $output = [pscustomobject]@{
                ComputerName = $server.NetName
                InstanceName = $server.ServiceName
                SqlInstance  = $instance
                Database     = $db
                Certificate  = $cert
                Status       = $null
            }

            if ($Pscmdlet.ShouldProcess($instance, "Dropping the certificate named $cert for database '$db' on $server")) {
                try {
                    $smocert.Drop()
                    Write-Message -Level Verbose -Message "Successfully removed certificate named $cert from the $db database on $server"
                    $output.status = "Success"
                }
                catch {
                    $output.Status = "Failure"
                    Stop-Function -Message "Failed to drop certificate named $cert from $db on $server." -Target $smocert -InnerErrorRecord $_ -Continue
                }
                $output
            }
        }
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
                $currentdb = $server.Databases[$db]

                if ($null -eq $currentdb) {
                    Stop-Function -Message "Database '$db' does not exist on $server" -Target $currentdb -Continue
                }

                if (-not $currentdb.IsAccessible) {
                    Stop-Function -Message "Database '$db' is not accessible" -Target $currentdb -Continue
                }

                foreach ($cert in $certificate) {
                    $smocert = $currentdb.Certificates[$cert]

                    if ($null -eq $smocert) {
                        Stop-Function -Message "No certificate named $cert exists in the $db database on $server" -Target $currentdb.Certificates -Continue
                    }

                    Drop-Cert -smocert $smocert
                }
            }
        }

        foreach ($smocert in $CertificateCollection) {
            Drop-Cert -smocert $smocert
        }
    }
}