function New-DbaDbEncryptionKey {
    <#
    .SYNOPSIS
        Creates a new database encryption key using encryption by server certificate

    .DESCRIPTION
        Creates a new database encryption key. If no database is specified, the encryption key will be created in master.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the encryption key will be created. Defaults to master.

    .PARAMETER Certificate
        The name of the certificate in master that will be used. Tries to find one if one is not specified.

    .PARAMETER EncryptionAlgorithm
        Specifies an encryption algorithm. Defaults to Aes256.

        Options are: "Aes128", "Aes192", "Aes256", "TripleDes"

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER Force
        Create an encryption key even though the specified cert has not been backed up

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/New-DbaDbEncryptionKey

    .EXAMPLE
        PS C:\> New-DbaDbEncryptionKey -SqlInstance Server1

        An encryption key will be used to do everything.

    .EXAMPLE
        PS C:\> New-DbaDbEncryptionKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts then hits it

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database = "master",
        [string]$Certificate,
        [ValidateSet("Aes128", "Aes192", "Aes256", "TripleDes")]
        [string]$EncryptionAlgorithm = 'Aes256',
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ((Test-Bound -Not -ParameterName Certificate)) {
                Write-Message -Level Verbose -Message "Name of certificate not specified, getting cert from '$db'"
                $null = $db.Parent.Databases["master"].Certificates.Refresh()
                $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master | Where-Object Name -notmatch "##"
                if ($dbcert.Name.Count -ne 1) {
                    if ($dbcert.Name.Count -lt 1) {
                        Stop-Function -Message "No usable certificates found in master" -Continue
                    } else {
                        Stop-Function -Message "More than one certificate found in master, please specify a name" -Continue
                    }
                } else {
                    $Certificate = $dbcert.Name
                }
            }

            $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master -Certificate $Certificate
            if ($dbcert.LastBackupDate.Year -eq 1 -and -not $Force) {
                Stop-Function -Message "Certificate ($Certificate) has not been backed up. Please backup your certificate or use -Force to continue" -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating encryption key for database '$($db.Name)'")) {

                # something is up with .net, force a stop
                $eap = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                # Shoutout to https://www.mssqltips.com/sqlservertip/6316/configure-sql-server-transparent-data-encryption-with-powershell/
                try {
                    $smoencryptionkey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey
                    $smoencryptionkey.Parent = $db
                    $smoencryptionkey.EncryptionAlgorithm = $EncryptionAlgorithm
                    $smoencryptionkey.EncryptionType = [Microsoft.SqlServer.Management.Smo.DatabaseEncryptionType]::ServerCertificate
                    $smoencryptionkey.EncryptorName = $Certificate
                    $null = $smoencryptionkey.Create()
                    $null = $smoencryptionkey.Parent.Refresh()
                    $null = $smoencryptionkey.Parent.Certficates.Refresh()
                    $db | Get-DbaDbEncryptionKey
                } catch {
                    $ErrorActionPreference = $eap
                    Stop-Function -Message "Failed to create encryption key in $($db.Name) on $($db.Parent.Name)" -Target $smoencryptionkey -ErrorRecord $_ -Continue
                }
                $ErrorActionPreference = $eap
            }
        }
    }
}